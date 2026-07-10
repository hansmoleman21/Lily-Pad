# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Lily Pad is a dog activity logger. Events are logged and queried from iPhone or Apple Watch
via Apple Shortcuts — no app install, no SMS. A Shortcut POSTs a JSON message to an AWS API
Gateway endpoint, which a Lambda parses, records to DynamoDB, and replies to with a friendly
(Siri-readable) confirmation. A read-only web dashboard renders recent history.

## Architecture

```
Apple Shortcut → API Gateway (HTTP POST /log) → Lambda (Python 3.12) → DynamoDB
Web dashboard  → API Gateway (HTTP GET  /data) → Lambda             → DynamoDB
Dashboard HTML → S3 (private) → CloudFront (HTTPS)
```

- **`lambda/handler.py`** — Lambda entry point (`lambda_handler`). Decodes the request body,
  routes `GET /data` to `handle_dashboard_data()`, and otherwise treats the request as a
  Shortcuts `POST /log`: validates the `x-api-key` header with a constant-time compare
  (`hmac.compare_digest`), parses the JSON `{"text": ...}` body (capped at `MAX_TEXT_LEN`),
  dispatches to `handle_message()`, and returns a plain-text reply.
- **`lambda/phrases.py`** — All trigger phrases for recording and querying events. Edit here to
  add voice-to-text aliases or new event types.
- **`dashboard/index.html.tpl`, `dashboard/public.html.tpl`** — Dashboard templates. Terraform
  renders them with the `/data` URL (and, for the private page, the dashboard token) and
  uploads them to S3 (served via CloudFront). The public dashboard is the CloudFront root;
  the private page (token embedded) is served at an unguessable path,
  `lily-<random_id>.html` — get it with `terraform output -raw private_dashboard_url`. All
  server-derived values are HTML-escaped via `esc()` before hitting `innerHTML`.
- **`terraform/`** — All AWS infrastructure: DynamoDB table, Lambda, API Gateway v2 (`/log`
  and `/data` routes, CORS locked to the CloudFront origin), IAM roles, CloudWatch log groups
  (30-day retention), CloudFront security headers, and the S3 + CloudFront dashboard. State is
  stored in an S3 backend (see `terraform/main.tf`).
- **`tests/`** — pytest suite (moto-mocked DynamoDB/SSM). Run with `.venv/bin/pytest` after
  `python3 -m venv .venv && .venv/bin/pip install -r requirements-dev.txt`.

### DynamoDB Schema

Table: `lily-events`
- Partition key: `event_type` (String) — e.g. `poop`, `pee`, `vomit`, `ate_ground`, `walk`,
  `medicine`, `weight`, `note`, `bath`, `brush`
- Sort key: `timestamp` (String, ISO 8601 UTC)
- Optional attribute: `attribute` — meaning varies by event type (e.g. `normal`/`soft`/`diarrhea`
  for poop, walk duration in minutes, weight in lbs, free-form text for notes/medicine)

### Secret handling

Two secrets live in SSM Parameter Store as SecureStrings, both created manually (never
Terraform-managed, so they don't pass through tfvars or state):

- `/lily-pad/shortcuts-api-key` — validated on `POST /log` (`x-api-key` header). If
  `API_KEY_SSM_PATH` is unset or the fetch fails, **all `/log` requests are rejected**
  (fail-closed).
- `/lily-pad/dashboard-token` — sent by the private dashboard as `x-dashboard-token`. A valid
  token unlocks the full `GET /data` payload; anything else gets a public payload with
  `note`/`medicine`/`weight` withheld (`PUBLIC_EXCLUDED_TYPES`), so the public dashboard keeps
  working without a token.

Lambda fetches each once per container (`get_api_key()` / `get_dashboard_token()`, both
`lru_cache`d over `_fetch_ssm_secret`); neither value appears in Lambda env vars in plaintext.
Note the `not api_key` / `bool(token)` guards are load-bearing: `hmac.compare_digest("", "")`
is `True`, so an empty configured secret must never compare successfully.

### Phrase matching

`handle_message()` dispatches in priority order. Management and query phrases are checked before
recording phrases so that, e.g., "last poop?" doesn't accidentally log an event. Within
`match_record()`, attribute-specific phrases are checked before base phrases (so "soft poop" →
`poop/soft`, not `poop/normal`). All phrases are matched case-insensitively as substrings.

### Timezone note

Timestamps are stored in UTC ISO 8601 and displayed in US Pacific. Time handling uses
`zoneinfo.ZoneInfo("America/Los_Angeles")` (the `PACIFIC` constant in `handler.py`), so DST is
handled automatically — no manual offset to update.

## Deploy / Teardown

Full one-time setup (AWS account, MFA, CLI profile, tfenv, S3 state bucket, and creating the
`/lily-pad/shortcuts-api-key` and `/lily-pad/dashboard-token` SSM parameters) is documented in
`README.md`. No tfvars file is needed. Once that's done:

```bash
cd terraform
terraform init
terraform apply    # deploys everything; prints log_url
terraform destroy  # tears down all AWS resources
```

Terraform zips `lambda/` automatically (via `archive_file`) — no manual packaging step.

## Testing

```bash
python3 -m venv .venv                            # one-time
.venv/bin/pip install -r requirements-dev.txt    # one-time
.venv/bin/pytest
```

Tests cover phrase matching, Pacific time parsing (incl. DST), DynamoDB helpers (moto), and
`lambda_handler` routing/auth. Run them before every deploy.

## Updating Lambda Code

After editing `lambda/handler.py` or `lambda/phrases.py`, run the tests, then re-run
`terraform apply`. Terraform detects the zip hash change and updates the function automatically.

## Adding a New Event Type

1. Add the event type and trigger phrases to `RECORD` in `lambda/phrases.py`.
2. Add query phrases to `QUERY` if you want "last X?" / "how many X today?" support.
3. Add a display label entry to `EVENT_LABELS` in `lambda/handler.py`.
4. Re-deploy with `terraform apply`.
