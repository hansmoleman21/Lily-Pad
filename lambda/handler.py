"""
Lily Pad — SMS handler Lambda

Receives inbound Twilio webhooks, parses the message body, writes events to
DynamoDB, and replies with a TwiML SMS response.

Environment variables
---------------------
DYNAMODB_TABLE              : DynamoDB table name (lily-events)
TWILIO_ACCOUNT_SID          : Twilio Account SID (informational, not used in validation)
TWILIO_AUTH_TOKEN_SSM_PATH  : SSM Parameter Store path for the Twilio Auth Token
                              (e.g. /lily-pad/twilio-auth-token)
                              Leave unset to skip signature validation (dev only).
ALLOWED_PHONE_NUMBERS       : Comma-separated E.164 numbers allowed to log events.
                              Leave empty to allow all (fine if it's just you).
"""

import base64
import hashlib
import hmac
import os
import urllib.parse
import xml.sax.saxutils
from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo
from typing import Optional, Tuple

import boto3
from boto3.dynamodb.conditions import Key

from phrases import RECORD, QUERY, SUMMARY, DELETE

# ── Config ────────────────────────────────────────────────────────────────────

TABLE_NAME = os.environ["DYNAMODB_TABLE"]
ALLOWED_NUMBERS = set(
    filter(None, os.environ.get("ALLOWED_PHONE_NUMBERS", "").split(","))
)

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(TABLE_NAME)


def _fetch_ssm_secret(path: str) -> str:
    """Fetch a SecureString from SSM Parameter Store at cold start."""
    if not path:
        return ""
    try:
        client = boto3.client("ssm")
        resp = client.get_parameter(Name=path, WithDecryption=True)
        return resp["Parameter"]["Value"]
    except Exception as e:
        print(f"WARNING: Could not fetch SSM parameter '{path}': {e}")
        return ""


# Fetched once per Lambda container lifetime (cold start only)
AUTH_TOKEN = _fetch_ssm_secret(
    os.environ.get("TWILIO_AUTH_TOKEN_SSM_PATH", "")
)

# ── Event display labels ──────────────────────────────────────────────────────

EVENT_LABELS = {
    "poop":       ("pooped",                        "poops"),
    "pee":        ("peed",                          "pees"),
    "vomit":      ("vomited",                       "vomits"),
    "ate_ground": ("ate something off the ground",  "times eating off the ground"),
}

# ── Time helpers ──────────────────────────────────────────────────────────────

PACIFIC = ZoneInfo("America/Los_Angeles")


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def iso_now() -> str:
    return now_utc().isoformat(timespec="seconds")


def start_of_today_utc() -> str:
    d = now_utc().replace(hour=0, minute=0, second=0, microsecond=0)
    return d.isoformat(timespec="seconds")


def start_of_today_pacific() -> str:
    """Midnight Pacific time today, expressed as a UTC ISO 8601 string for DynamoDB queries."""
    midnight_pacific = datetime.now(PACIFIC).replace(hour=0, minute=0, second=0, microsecond=0)
    return midnight_pacific.astimezone(timezone.utc).isoformat(timespec="seconds")


def format_time(iso: str) -> str:
    """Convert a UTC ISO 8601 string to a friendly display string."""
    dt = datetime.fromisoformat(iso).replace(tzinfo=timezone.utc)
    # Hardcoded to US Eastern. Change -5 to -4 during Daylight Saving Time,
    # or replace with a proper timezone library (e.g. zoneinfo) if desired.
    eastern = dt.astimezone(timezone(timedelta(hours=-5)))
    now_eastern = now_utc().astimezone(timezone(timedelta(hours=-5)))
    time_str = eastern.strftime("%-I:%M %p")
    if eastern.date() == now_eastern.date():
        return f"today at {time_str}"
    elif eastern.date() == (now_eastern - timedelta(days=1)).date():
        return f"yesterday at {time_str}"
    else:
        return eastern.strftime("%b %-d at ") + time_str


# ── DynamoDB helpers ──────────────────────────────────────────────────────────

def record_event(event_type: str, attribute: Optional[str]) -> str:
    """Write an event to DynamoDB. Returns the ISO timestamp that was stored."""
    ts = iso_now()
    item: dict = {"event_type": event_type, "timestamp": ts}
    if attribute is not None:
        item["attribute"] = attribute
    table.put_item(Item=item)
    return ts


def query_last(event_type: str) -> Optional[dict]:
    """Return the most recent event item dict, or None."""
    resp = table.query(
        KeyConditionExpression=Key("event_type").eq(event_type),
        ScanIndexForward=False,
        Limit=1,
    )
    items = resp.get("Items", [])
    return items[0] if items else None


def delete_last_event() -> Optional[dict]:
    """Find and delete the most recent event across all event types. Returns the deleted item or None."""
    candidates = []
    for event_type in EVENT_LABELS:
        item = query_last(event_type)
        if item:
            candidates.append(item)
    if not candidates:
        return None
    latest = max(candidates, key=lambda x: x["timestamp"])
    table.delete_item(Key={"event_type": latest["event_type"], "timestamp": latest["timestamp"]})
    return latest


def query_count_today(event_type: str) -> int:
    """Return the number of events of this type since midnight UTC today."""
    resp = table.query(
        KeyConditionExpression=(
            Key("event_type").eq(event_type)
            & Key("timestamp").gte(start_of_today_utc())
        ),
        Select="COUNT",
    )
    return resp["Count"]


def query_today_events(event_type: str) -> list:
    """Return all event items for this type since midnight Pacific time today."""
    resp = table.query(
        KeyConditionExpression=(
            Key("event_type").eq(event_type)
            & Key("timestamp").gte(start_of_today_pacific())
        ),
    )
    return resp.get("Items", [])


SUMMARY_LABELS = {
    "poop":       "Poops",
    "pee":        "Pees",
    "vomit":      "Vomits",
    "ate_ground": "Ate ground",
}


def build_summary_today() -> str:
    lines = ["Today's summary:"]
    for event_type, label in SUMMARY_LABELS.items():
        items = query_today_events(event_type)
        count = len(items)
        if count > 0 and event_type in ("poop", "vomit"):
            attr_counts: dict = {}
            for item in items:
                attr = item.get("attribute", "unspecified")
                attr_counts[attr] = attr_counts.get(attr, 0) + 1
            attr_str = ", ".join(f"{v} {k}" for k, v in attr_counts.items())
            lines.append(f"{label}: {count} ({attr_str})")
        else:
            lines.append(f"{label}: {count}")
    return "\n".join(lines)


# ── Phrase matching ───────────────────────────────────────────────────────────

def _contains(text: str, phrase: str) -> bool:
    return phrase.lower() in text.lower()


def match_record(text: str) -> Optional[Tuple[str, Optional[str]]]:
    """
    Returns (event_type, attribute) if the text matches a recording phrase.
    Checks attribute-specific phrases before base phrases so that
    e.g. "soft poop" is captured as poop/soft rather than poop/normal.
    Returns None if no match.
    """
    for event_type, config in RECORD.items():
        if isinstance(config, list):
            for phrase in config:
                if _contains(text, phrase):
                    return (event_type, None)
        else:
            # Check attribute-specific phrases first
            for attr, phrases in config.get("attributes", {}).items():
                for phrase in phrases:
                    if _contains(text, phrase):
                        return (event_type, attr)
            # Fall back to base phrases
            for phrase in config.get("base", []):
                if _contains(text, phrase):
                    return (event_type, config.get("default_attribute"))

    return None


def match_delete(text: str) -> bool:
    return any(_contains(text, phrase) for phrase in DELETE)


def match_query(text: str) -> Optional[Tuple[str, str]]:
    """
    Returns (event_type, query_kind) if the text matches a query phrase.
    Returns None if no match.
    """
    for kind, events in QUERY.items():
        for event_type, phrases in events.items():
            for phrase in phrases:
                if _contains(text, phrase):
                    return (event_type, kind)
    return None


# ── Message handling ──────────────────────────────────────────────────────────

def handle_message(body: str) -> str:
    # Delete takes priority over everything else
    if match_delete(body):
        deleted = delete_last_event()
        if deleted is None:
            return "No records found to delete."
        event_type = deleted["event_type"]
        past_tense, _ = EVENT_LABELS[event_type]
        attr = deleted.get("attribute")
        attr_str = f" ({attr})" if attr else ""
        return f"Deleted: Lily {past_tense}{attr_str} {format_time(deleted['timestamp'])}."

    # Queries take priority over recording (so "last poop?" doesn't accidentally log a poop)
    query_match = match_query(body)
    if query_match:
        event_type, kind = query_match
        past_tense, plural = EVENT_LABELS[event_type]
        if kind == "last":
            item = query_last(event_type)
            if item is None:
                return f"No record of Lily having {past_tense} yet."
            attr = item.get("attribute")
            attr_str = f" ({attr})" if attr else ""
            return f"Lily last {past_tense}{attr_str} {format_time(item['timestamp'])}."
        else:  # count
            count = query_count_today(event_type)
            if count == 0:
                return f"Lily hasn't had any {plural} today."
            noun = plural.rstrip("s") if (count == 1 and plural.endswith("s")) else plural
            return f"Lily has had {count} {noun} today."

    # Recording
    record_match = match_record(body)
    if record_match:
        event_type, attribute = record_match
        ts = record_event(event_type, attribute)
        past_tense, _ = EVENT_LABELS[event_type]
        attr_str = f" ({attribute})" if attribute else ""
        return f"Recorded: Lily {past_tense}{attr_str} {format_time(ts)}."

    return (
        "Didn't catch that. Try:\n"
        "poop / soft poop / diarrhea\n"
        "peed\n"
        "vomited / bile / food\n"
        "ate off the ground\n"
        "last poop? / how many pees today?"
    )


# ── Twilio signature validation ───────────────────────────────────────────────

def validate_twilio_signature(event: dict, raw_body: str) -> bool:
    """
    Validates the X-Twilio-Signature header using HMAC-SHA1.
    Returns True if AUTH_TOKEN is unset (dev mode) or signature matches.
    See: https://www.twilio.com/docs/usage/webhooks/webhooks-security
    """
    if not AUTH_TOKEN:
        return True

    headers = event.get("headers") or {}
    signature = headers.get("x-twilio-signature", "")

    # Reconstruct the URL as Twilio sees it.
    # In API Gateway v2, the 'host' header is the API Gateway domain — reliable.
    host = headers.get("host", "")
    path = event.get("rawPath", "/sms")
    url = f"https://{host}{path}"

    params = dict(urllib.parse.parse_qsl(raw_body))

    # Twilio's algorithm: URL + alphabetically sorted param name+value pairs
    validation_string = url + "".join(
        f"{k}{v}" for k, v in sorted(params.items())
    )
    expected_bytes = hmac.new(
        AUTH_TOKEN.encode(), validation_string.encode(), hashlib.sha1
    ).digest()
    expected_b64 = base64.b64encode(expected_bytes).decode()

    return hmac.compare_digest(expected_b64, signature)


# ── Lambda entry point ────────────────────────────────────────────────────────

def twiml_response(message: str) -> dict:
    # XML-escape the message to prevent injection if message content ever changes
    escaped = xml.sax.saxutils.escape(message)
    body = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        f"<Response><Message>{escaped}</Message></Response>"
    )
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "text/xml"},
        "body": body,
    }


def lambda_handler(event: dict, context) -> dict:
    # Decode body once; reuse for both signature validation and param parsing
    raw_body = event.get("body", "") or ""
    if event.get("isBase64Encoded"):
        raw_body = base64.b64decode(raw_body).decode("utf-8")

    if not validate_twilio_signature(event, raw_body):
        return {"statusCode": 403, "body": "Forbidden"}

    params = dict(urllib.parse.parse_qsl(raw_body))
    from_number = params.get("From", "")
    sms_body = params.get("Body", "").strip()

    if ALLOWED_NUMBERS and from_number not in ALLOWED_NUMBERS:
        return twiml_response("Sorry, you're not authorized to use Lily Pad.")

    reply = handle_message(sms_body)
    return twiml_response(reply)
