# Lily Pad

SMS-based dog activity logger. Text a Twilio number to log Lily's events and
query recent history. Works from iPhone and Apple Watch with no app install.

## Setup

### 1. AWS account

1. Create a free AWS account at https://aws.amazon.com
2. In the IAM console, create an IAM user with **programmatic access**
   (or use IAM Identity Center for SSO — either works)
3. Attach the `AdministratorAccess` policy to that user
   _(you can lock this down later once everything is running)_
4. Save the Access Key ID and Secret Access Key
5. Install the AWS CLI: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html
6. Run `aws configure` and paste in your credentials + region (e.g. `us-east-1`)

### 2. Twilio account

1. Sign up at https://www.twilio.com (free trial gives ~$15 credit)
2. In the Twilio Console, buy a phone number (~$1/month)
3. Note your **Account SID** and **Auth Token** from the Console dashboard

### 3. Terraform

Install Terraform: https://developer.hashicorp.com/terraform/install

### 4. Deploy

```bash
cd terraform

# Create a tfvars file with your secrets (never commit this)
cat > terraform.tfvars <<EOF
twilio_account_sid    = "ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
twilio_auth_token     = "your_auth_token_here"
allowed_phone_numbers = "+15555550100"   # your phone number in E.164 format
EOF

terraform init
terraform apply
```

After `apply` succeeds, Terraform prints the webhook URL:

```
webhook_url = "https://xxxxxxxx.execute-api.us-east-1.amazonaws.com/sms"
```

### 5. Wire up Twilio

1. In the Twilio Console, go to **Phone Numbers → Manage → Active Numbers**
2. Click your number
3. Under **Messaging → A message comes in**, set:
   - **Webhook**: paste the `webhook_url` from Terraform output
   - **HTTP method**: `HTTP POST`
4. Save

## Usage

Text your Twilio number:

| Message | Effect |
|---|---|
| `lily pooped` | Logs a poop event |
| `lily peed` | Logs a pee event |
| `lily vomited` | Logs a vomit event |
| `lily ate something off the ground` | Logs an ate_ground event |
| `last poop?` | Replies with the time of the last poop |
| `how many pees today?` | Replies with today's pee count |

## Costs

~$1–2/month (Twilio phone number + SMS; AWS is within free tier).
