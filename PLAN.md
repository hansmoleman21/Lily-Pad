# Lily Pad — Dog Activity Logger

An SMS-based app to log Lily's activity (pees, poops, vomits, eating off the ground).
Works natively from iPhone and Apple Watch — no app installation required.

## Architecture

```
Your phone (SMS)
      ↕
Twilio phone number
      ↕  (webhook POST)
AWS API Gateway → AWS Lambda → DynamoDB
```

### Components

| Component | Purpose |
|---|---|
| **Twilio** | Inbound/outbound SMS. Provides a phone number, handles webhooks. ~$1/month + ~$0.008/message |
| **AWS API Gateway** | HTTPS endpoint that Twilio POSTs inbound messages to |
| **AWS Lambda (Python)** | Parses SMS, reads/writes DynamoDB, formats SMS reply |
| **AWS DynamoDB** | Stores activity events with timestamps. Serverless, essentially free at this usage level |
| **Terraform** | Manages all AWS infrastructure as code |

## How It Works

### Recording events
Send a text to the Twilio number — keyword matching triggers a write to DynamoDB:

| Text | Recorded as |
|---|---|
| "lily pooped" | `{type: "poop", timestamp: <now>}` |
| "lily peed" | `{type: "pee", timestamp: <now>}` |
| "lily vomited" | `{type: "vomit", timestamp: <now>}` |
| "lily ate something off the ground" | `{type: "ate_ground", timestamp: <now>}` |

### Querying events
Ask questions — pattern matching triggers a DynamoDB query and an SMS reply:

| Text | Reply |
|---|---|
| "last poop?" | "Lily last pooped at 2:34 PM today" |
| "how many pees today?" | "Lily peed 3 times today" |
| "last vomit?" | "Lily last vomited yesterday at 9:12 AM" |

No LLM needed — the vocabulary is small enough that regex/keyword matching is simpler and more reliable.

## Build Steps

1. **Set up accounts**
   - [ ] AWS account created
   - [ ] AWS CLI installed and configured with credentials
   - [ ] Twilio account created (free trial works to start)
   - [ ] Terraform installed locally

2. **Set up Terraform project structure**
   - [ ] `main.tf`, `variables.tf`, `outputs.tf`
   - [ ] S3 backend for remote Terraform state (optional but recommended)
   - [ ] IAM role + policy for Lambda

3. **Define DynamoDB schema**
   - [ ] Table: `lily-events`
   - [ ] Partition key: `event_type` (String)
   - [ ] Sort key: `timestamp` (String, ISO 8601)

4. **Write the Lambda function**
   - [ ] Parse inbound Twilio webhook payload
   - [ ] Keyword matching for recording events
   - [ ] Query logic for questions
   - [ ] Format and return TwiML SMS response

5. **Wire up API Gateway + Twilio**
   - [ ] API Gateway HTTP API with POST route
   - [ ] Lambda integration
   - [ ] Configure Twilio webhook URL to point at API Gateway endpoint

## Estimated Costs

| Service | Cost |
|---|---|
| Twilio phone number | ~$1/month |
| Twilio SMS (send/receive) | ~$0.008/message |
| Lambda, API Gateway, DynamoDB | Within AWS free tier |
| **Total** | **~$1-2/month** |
