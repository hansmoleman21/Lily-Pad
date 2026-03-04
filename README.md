# Lily Pad

SMS-based dog activity logger. Text a Twilio number to log Lily's events and
query recent history. Works from iPhone and Apple Watch with no app install.

## Setup

### 1. AWS account

1. Create a free AWS account at https://aws.amazon.com
2. In the IAM console, create an IAM user named `lily-pad-admin` with programmatic access
3. Attach the policy from `iam/lily-pad-admin-policy.json` — scoped to only what's needed, with MFA required for all operations
4. Set up an MFA device for the user (see `admin-notes.md`)
5. Install the AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html
6. Run `aws configure --profile lily-pad-admin` and enter your credentials and region (`us-west-2`)

Before each Terraform session, get temporary credentials using your MFA code (see `admin-notes.md`).

### 2. Twilio account

1. Sign up at https://www.twilio.com (free trial gives ~$15 credit)
2. In the Twilio Console, buy a phone number (~$1/month)
3. Note your **Account SID** and **Auth Token** from the Console dashboard

### 3. Terraform

Install [tfenv](https://github.com/tfutils/tfenv) to manage Terraform versions:

```bash
brew install tfenv
tfenv install  # reads .terraform-version automatically
```

### 4. Create SSM parameters

All secrets and personal data are stored in SSM Parameter Store — nothing sensitive goes in source code or `tfvars`.

Create these parameters before deploying (see `admin-notes.md` for the full commands):

| Parameter | Description |
|---|---|
| `/lily-pad/twilio-auth-token` | Twilio Auth Token |
| `/lily-pad/shortcuts-api-key` | API key for the Apple Shortcuts `/log` endpoint |

### 5. Deploy

```bash
cd terraform

# Create a tfvars file with your secrets (never commit this)
cat > terraform.tfvars <<EOF
twilio_account_sid = "ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
shortcuts_api_key  = "your-random-secret-key"
EOF

terraform init
terraform apply
```

After `apply` succeeds, Terraform prints the URLs:

```
webhook_url = "https://xxxxxxxx.execute-api.us-west-2.amazonaws.com/sms"
log_url     = "https://xxxxxxxx.execute-api.us-west-2.amazonaws.com/log"
```

### 6. Wire up Twilio

1. In the Twilio Console, go to **Phone Numbers → Manage → Active Numbers**
2. Click your number
3. Under **Messaging → A message comes in**, set:
   - **Webhook**: paste the `webhook_url` from Terraform output
   - **HTTP method**: `HTTP POST`
4. Save

### 7. Apple Shortcuts (optional)

The `/log` endpoint lets you log events from iPhone or Apple Watch without SMS — useful for quick taps from a widget or watch complication.

**Build the shortcut:**

1. Open the Shortcuts app and create a new shortcut
2. Add a **Get Contents of URL** action with:
   - **URL**: the `log_url` from Terraform output
   - **Method**: POST
   - **Headers**: `x-api-key: <your-shortcuts-api-key>`, `Content-Type: application/json`
   - **Request Body**: JSON — `{"text": "poop"}` (or any phrase from the Usage section)
3. Optionally add a **Show Result** action to display the confirmation message

**Tips:**
- Duplicate the shortcut for each event type you want a one-tap button for
- Or use an **Ask for Input** / **Choose from Menu** action for a flexible single shortcut
- Add the shortcut to your Home Screen or Apple Watch for quick access

## Usage

Text your Twilio number:

### Logging events

| Message | Logged as |
|---|---|
| `poop` / `pooped` | Poop (normal) |
| `soft poop` | Poop (soft) |
| `diarrhea` | Poop (diarrhea) |
| `peed` / `pee` | Pee |
| `vomited` / `threw up` | Vomit |
| `bile` / `vomited bile` | Vomit (bile) |
| `vomited food` | Vomit (food) |
| `ate off the ground` | Ate ground |

### Querying

| Message | Response |
|---|---|
| `last poop?` | Time of the last poop |
| `how many pees today?` | Today's pee count |
| `summary` / `summary today` | Full breakdown of today's events |

### Managing records

| Message | Effect |
|---|---|
| `remove last` / `undo` | Deletes the most recent entry |

Phrases are matched case-insensitively as substrings — voice-to-text friendly.
Edit `lambda/phrases.py` to add aliases or new event types.

## Costs

~$1–2/month (Twilio phone number + SMS; AWS usage is within free tier).
