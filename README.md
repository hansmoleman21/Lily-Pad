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

### 7. Create the SSM parameter (one-time, before terraform apply)

The Shortcuts API key is stored in SSM Parameter Store — nothing sensitive goes in source code, `tfvars`, or Terraform-managed resources. Generate a random value and store it:

```bash
aws ssm put-parameter \
  --name "/lily-pad/shortcuts-api-key" \
  --value "$(openssl rand -hex 32)" \
  --type SecureString \
  --region us-west-2
```

| Parameter | Description |
|---|---|
| `/lily-pad/shortcuts-api-key` | API key for the Apple Shortcuts `/log` endpoint |

The private dashboard needs no secret: it uses Okta login (an OIDC single-page app, PKCE, no
client secret). Create the `lily-pad-dashboard` SPA app in Okta with sign-in redirect URI
`https://<cloudfront-domain>/index.html`, and pass its client ID to Terraform as
`okta_dashboard_client_id` (e.g. in the gitignored `terraform/terraform.tfvars`).

Retrieve a value later (e.g. for the Apple Shortcut header):

```bash
aws ssm get-parameter --name "/lily-pad/shortcuts-api-key" \
  --with-decryption --query Parameter.Value --output text --region us-west-2
```

To rotate the key: `aws ssm put-parameter --overwrite` with a new value, update the
`x-api-key` header in your Apple Shortcuts, then re-run
`terraform apply` so new Lambda containers pick it up (any code/config change forces this;
otherwise wait for containers to recycle or update the function config manually).

### 8. Deploy

```bash
lambda/build.sh          # packages handler + pinned deps into lambda/build/
cd terraform
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

## Backups & restore

The `lily-events` table has three layers of protection against accidental loss:

1. **`prevent_destroy`**: any Terraform plan that would destroy or replace the table fails
   at plan time, before anything touches AWS.
2. **Deletion protection**: AWS refuses to delete the table, whether from Terraform, the
   console or the CLI.
3. **Point-in-time recovery (PITR)**: 35 days of restorable history, plus a system backup
   kept for 35 days if the table is deleted anyway.

For a deliberate teardown:

1. In `terraform/main.tf`, remove the `lifecycle { prevent_destroy = true }` block and set
   `deletion_protection_enabled = false`. Then run `terraform apply`.
2. Run `terraform destroy`.

Do restores in the DynamoDB console with an identity that has data access. The Terraform
and CI identities deliberately can't read or write items.

- **Table was deleted:** open DynamoDB → Backups. Restore the system backup
  `lily-events$DeletedTableBackup` as `lily-events`. If Terraform did the delete, run
  `terraform import aws_dynamodb_table.lily_events lily-events`. Then run `terraform apply`.
  A restored table doesn't inherit PITR, deletion protection or tags, and the apply puts
  them back.
- **Bad data, table intact:** restore the table to a point in time as a *new* table (e.g.
  `lily-events-restore-YYYYMMDD`). Inspect it, copy back the items you need, then delete
  the restore table.

## Costs

~$0.50/month (AWS usage is within free tier for typical household use). PITR is billed per
GB of table size (~$0.20/GB-month). At this table's size (well under 1 MB) that's effectively $0.
