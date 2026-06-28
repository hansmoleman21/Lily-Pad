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
  (`hmac.compare_digest`), parses the JSON `{"text": ...}` body, dispatches to
  `handle_message()`, and returns a plain-text reply.
- **`lambda/phrases.py`** — All trigger phrases for recording and querying events. Edit here to
  add voice-to-text aliases or new event types.
- **`dashboard/index.html.tpl`, `dashboard/public.html.tpl`** — Dashboard templates. Terraform
  renders them with the `/data` URL and uploads them to S3 (served via CloudFront).
- **`terraform/`** — All AWS infrastructure: DynamoDB table, Lambda, API Gateway v2 (`/log`
  and `/data` routes), IAM roles, the SSM parameter for the API key, and the S3 + CloudFront
  dashboard. State is stored in an S3 backend (see `terraform/main.tf`).

### DynamoDB Schema

Table: `lily-events`
- Partition key: `event_type` (String) — e.g. `poop`, `pee`, `vomit`, `ate_ground`, `walk`,
  `medicine`, `weight`, `note`, `bath`, `brush`
- Sort key: `timestamp` (String, ISO 8601 UTC)
- Optional attribute: `attribute` — meaning varies by event type (e.g. `normal`/`soft`/`diarrhea`
  for poop, walk duration in minutes, weight in lbs, free-form text for notes/medicine)

### Secret handling

The Apple Shortcuts API key is stored in SSM Parameter Store as a SecureString at
`/lily-pad/shortcuts-api-key`. Lambda fetches it once per cold start (`_fetch_ssm_secret`),
keyed off the `API_KEY_SSM_PATH` env var; the key never appears in Lambda env vars in plaintext.
If `API_KEY_SSM_PATH` is unset, API-key validation is skipped (dev only).

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
`/lily-pad/shortcuts-api-key` SSM parameter) is documented in `README.md`. Once that's done:

```bash
cd terraform

# First-time setup — create terraform.tfvars (never commit this file; it is .gitignored)
cat > terraform.tfvars <<EOF
shortcuts_api_key = "your-random-secret-key"
EOF

terraform init
terraform apply    # deploys everything; prints log_url
terraform destroy  # tears down all AWS resources
```

Terraform zips `lambda/` automatically (via `archive_file`) — no manual packaging step.

## Updating Lambda Code

After editing `lambda/handler.py` or `lambda/phrases.py`, re-run `terraform apply`. Terraform
detects the zip hash change and updates the function automatically.

## Adding a New Event Type

1. Add the event type and trigger phrases to `RECORD` in `lambda/phrases.py`.
2. Add query phrases to `QUERY` if you want "last X?" / "how many X today?" support.
3. Add a display label entry to `EVENT_LABELS` in `lambda/handler.py`.
4. Re-deploy with `terraform apply`.
