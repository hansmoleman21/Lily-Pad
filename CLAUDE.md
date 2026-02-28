# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Lily Pad is an SMS-based dog activity logger. Texts to a Twilio number are POSTed to AWS API Gateway → Lambda → DynamoDB. No app install required; works from iPhone and Apple Watch.

## Architecture

```
SMS → Twilio → API Gateway (HTTP POST /sms) → Lambda (Python 3.12) → DynamoDB
```

- **`lambda/handler.py`** — Lambda entry point. Validates Twilio signatures (HMAC-SHA1), parses form-encoded webhook payloads, dispatches to `handle_message()`, returns TwiML.
- **`lambda/phrases.py`** — All trigger phrases for recording and querying events. Edit here to add voice-to-text aliases or new event types.
- **`terraform/`** — All AWS infrastructure: DynamoDB table, Lambda, API Gateway v2, IAM roles, SSM parameter for the Twilio auth token.

### DynamoDB Schema

Table: `lily-events`
- Partition key: `event_type` (String) — e.g. `poop`, `pee`, `vomit`, `ate_ground`
- Sort key: `timestamp` (String, ISO 8601 UTC)
- Optional attribute: `attribute` (e.g. `normal`, `soft`, `diarrhea`, `bile`, `food`)

### Secret handling

The Twilio auth token is stored in SSM Parameter Store as a SecureString at `/lily-pad/twilio-auth-token`. Lambda fetches it once per cold start. The token never appears in Lambda env vars in plaintext.

### Phrase matching

`match_query()` is checked before `match_record()` so a message like "last poop?" doesn't accidentally log an event. Within `RECORD`, attribute-specific phrases are checked before base phrases (so "soft poop" → `poop/soft`, not `poop/normal`).

### Timezone note

`format_time()` in `handler.py` is hardcoded to US Eastern (`UTC-5`). Update the `timedelta(hours=-5)` to `-4` during Daylight Saving Time, or switch to `zoneinfo` for automatic DST handling.

## Deploy / Teardown

```bash
cd terraform

# First-time setup — create terraform.tfvars with secrets (never commit this file)
cat > terraform.tfvars <<EOF
twilio_account_sid    = "ACxxxx"
twilio_auth_token     = "your_token"
allowed_phone_numbers = "+15555550100"
EOF

terraform init
terraform apply    # deploys everything; prints webhook_url
terraform destroy  # tears down all AWS resources
```

Terraform zips `lambda/` automatically (via `archive_file`) — no manual packaging step.

## Updating Lambda Code

After editing `lambda/handler.py` or `lambda/phrases.py`, re-run `terraform apply`. Terraform detects the zip hash change and updates the function automatically.

## Adding a New Event Type

1. Add the event type and trigger phrases to `RECORD` in `lambda/phrases.py`.
2. Add query phrases to `QUERY` if you want "last X?" / "how many X today?" support.
3. Add a display label entry to `EVENT_LABELS` in `lambda/handler.py`.
4. Re-deploy with `terraform apply`.
