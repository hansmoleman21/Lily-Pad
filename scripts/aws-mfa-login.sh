#!/bin/bash
# Obtain temporary AWS credentials using MFA and export them to the current shell.
#
# Usage:  source scripts/aws-mfa-login.sh
#
# Must be sourced (not executed) so the exports persist in your shell session.
# Credentials are valid for 8 hours. To clear them:
#   unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

PROFILE="lily-pad-admin"
MFA_DEVICE_NAME="lily-pad-admin-mfa"
DURATION=28800  # 8 hours

ACCOUNT_ID=$(aws sts get-caller-identity --profile "$PROFILE" --query Account --output text 2>/dev/null)
if [ -z "$ACCOUNT_ID" ]; then
    echo "Error: could not get account ID. Is the '$PROFILE' profile configured?"
    return 1
fi

MFA_SERIAL="arn:aws:iam::${ACCOUNT_ID}:mfa/${MFA_DEVICE_NAME}"

printf "MFA token code: "
read -r TOKEN_CODE

OUTPUT=$(aws sts get-session-token \
    --profile "$PROFILE" \
    --serial-number "$MFA_SERIAL" \
    --token-code "$TOKEN_CODE" \
    --duration-seconds "$DURATION" \
    --output json 2>&1)

if [ $? -ne 0 ]; then
    echo "Error: $OUTPUT"
    return 1
fi

export AWS_ACCESS_KEY_ID=$(echo "$OUTPUT"     | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['AccessKeyId'])")
export AWS_SECRET_ACCESS_KEY=$(echo "$OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['SecretAccessKey'])")
export AWS_SESSION_TOKEN=$(echo "$OUTPUT"     | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['SessionToken'])")
EXPIRATION=$(echo "$OUTPUT"                   | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['Expiration'])")

echo "Credentials exported. Valid until $EXPIRATION."
