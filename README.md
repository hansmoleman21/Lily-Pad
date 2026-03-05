# Lily Pad

Dog activity logger. Log Lily's events and query recent history from iPhone or Apple Watch via Apple Shortcuts — no app install, no SMS required.

## Setup

### 1. AWS account

1. Create a free AWS account at https://aws.amazon.com
2. In the IAM console, create an IAM user with programmatic access:
   - Go to IAM → Users → Create user
   - Enable programmatic access (access key)
3. Attach the policy from `iam/lily-pad-admin-policy.json`:
   - On the permissions step, choose "Attach policies directly" → Create inline policy
   - Paste the contents of `iam/lily-pad-admin-policy.json`
4. Save the Access Key ID and Secret Access Key in a password manager

### 2. MFA setup (one-time)

1. In the IAM console, go to your user → Security credentials
2. Assign MFA device → Authenticator app
3. Scan the QR code with your authenticator app (e.g. 1Password, Authy)
4. Enter two consecutive codes to confirm

### 3. AWS CLI

Install the AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html

```bash
aws configure --profile lily-pad
```

Enter your access key, secret, region (`us-west-2`), and output format (`json`).

### 4. Terraform

Install [tfenv](https://github.com/tfutils/tfenv) to manage Terraform versions:

```bash
brew install tfenv
tfenv install  # reads .terraform-version automatically
```

### 5. S3 state bucket (one-time)

Create the S3 bucket used to store Terraform state:

```bash
aws s3api create-bucket \
  --bucket lily-pad-terraform-state-us-west-2 \
  --region us-west-2 \
  --create-bucket-configuration LocationConstraint=us-west-2 && \
aws s3api put-bucket-versioning \
  --bucket lily-pad-terraform-state-us-west-2 \
  --versioning-configuration Status=Enabled && \
aws s3api put-bucket-encryption \
  --bucket lily-pad-terraform-state-us-west-2 \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

### 6. Before each Terraform session

Get temporary credentials using your MFA code:

```bash
source scripts/aws-mfa-login.sh
```

Credentials are valid for 8 hours. Unset them when done:

```bash
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
```

### 7. Create SSM parameters (one-time, before terraform apply)

All secrets are stored in SSM Parameter Store — nothing sensitive goes in source code or `tfvars`.

Generate a random API key and store it:

```bash
openssl rand -hex 32

aws ssm put-parameter \
  --name "/lily-pad/shortcuts-api-key" \
  --value "your_generated_key_here" \
  --type SecureString \
  --region us-west-2
```

| Parameter | Description |
|---|---|
| `/lily-pad/shortcuts-api-key` | API key for the Apple Shortcuts `/log` endpoint |

### 8. Deploy

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

### 9. Apple Shortcuts

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
