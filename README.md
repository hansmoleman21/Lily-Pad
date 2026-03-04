# Lily Pad

Dog activity logger. Log Lily's events and query recent history from iPhone or Apple Watch via Apple Shortcuts — no app install, no SMS required.

## Setup

### 1. AWS account

1. Create a free AWS account at https://aws.amazon.com
2. In the IAM console, create an IAM user named `lily-pad-admin` with programmatic access
3. Attach the policy from `iam/lily-pad-admin-policy.json` — scoped to only what's needed, with MFA required for all operations
4. Set up an MFA device for the user (see `admin-notes.md`)
5. Install the AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html
6. Run `aws configure --profile lily-pad-admin` and enter your credentials and region (`us-west-2`)

Before each Terraform session, get temporary credentials using your MFA code (see `admin-notes.md`).

### 2. Terraform

Install [tfenv](https://github.com/tfutils/tfenv) to manage Terraform versions:

```bash
brew install tfenv
tfenv install  # reads .terraform-version automatically
```

### 3. Create SSM parameters

All secrets are stored in SSM Parameter Store — nothing sensitive goes in source code or `tfvars`.

Create this parameter before deploying (see `admin-notes.md` for the full command):

| Parameter | Description |
|---|---|
| `/lily-pad/shortcuts-api-key` | API key for the Apple Shortcuts `/log` endpoint |

### 4. Deploy

```bash
cd terraform

# Create a tfvars file with your secrets (never commit this)
cat > terraform.tfvars <<EOF
shortcuts_api_key = "your-random-secret-key"
EOF

terraform init
terraform apply
```

After `apply` succeeds, Terraform prints the URL:

```
log_url = "https://xxxxxxxx.execute-api.us-west-2.amazonaws.com/log"
```

### 5. Apple Shortcuts

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
- Use **Siri** to trigger shortcuts by name for hands-free logging

## Usage

Send any phrase below as the `text` field in a POST to `/log`.

### Logging events

| Text | Logged as |
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

| Text | Response |
|---|---|
| `last poop?` | Time of the last poop |
| `how many pees today?` | Today's pee count |
| `summary` / `summary today` | Last occurrence of each event type |

### Managing records

| Text | Effect |
|---|---|
| `remove last` / `undo` | Deletes the most recent entry |

Phrases are matched case-insensitively as substrings — voice-to-text friendly.
Edit `lambda/phrases.py` to add aliases or new event types.

## Costs

~$0.50/month (AWS usage is within free tier for typical household use).
