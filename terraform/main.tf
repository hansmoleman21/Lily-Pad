terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Recommended: enable this after creating an S3 bucket for state storage.
  # S3 keeps state off your laptop and supports encryption at rest.
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "lily-pad/terraform.tfstate"
  #   region = "us-west-2"
  #   encrypt = true
  # }
}

provider "aws" {
  region = var.aws_region
}

# ── Secrets (SSM Parameter Store) ────────────────────────────────────────────
# Stored as SecureString (AES-256 encrypted at rest).
# The Lambda reads this path at cold start — the actual token never appears
# in the Lambda configuration or environment variables.

resource "aws_ssm_parameter" "twilio_auth_token" {
  name  = "/lily-pad/twilio-auth-token"
  type  = "SecureString"
  value = var.twilio_auth_token

  tags = {
    Project = "lily-pad"
  }
}

# ── DynamoDB ──────────────────────────────────────────────────────────────────

resource "aws_dynamodb_table" "lily_events" {
  name         = "lily-events"
  billing_mode = "PAY_PER_REQUEST"

  hash_key  = "event_type"
  range_key = "timestamp"

  attribute {
    name = "event_type"
    type = "S"
  }

  attribute {
    name = "timestamp"
    type = "S"
  }

  tags = {
    Project = "lily-pad"
  }
}

# ── Lambda ────────────────────────────────────────────────────────────────────
# Zip the entire lambda/ directory so that phrases.py is included alongside
# handler.py. Output goes to terraform/ to keep it outside the source dir.

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda"
  output_path = "${path.module}/lambda_package.zip"
}

resource "aws_lambda_function" "lily_pad" {
  function_name    = "lily-pad"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE                  = aws_dynamodb_table.lily_events.name
      TWILIO_ACCOUNT_SID              = var.twilio_account_sid
      TWILIO_AUTH_TOKEN_SSM_PATH      = aws_ssm_parameter.twilio_auth_token.name
      ALLOWED_PHONE_NUMBERS_SSM_PATH  = "/lily-pad/allowed-phone-numbers"
    }
  }

  tags = {
    Project = "lily-pad"
  }
}

# ── API Gateway ───────────────────────────────────────────────────────────────

resource "aws_apigatewayv2_api" "lily_pad" {
  name          = "lily-pad"
  protocol_type = "HTTP"

  tags = {
    Project = "lily-pad"
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.lily_pad.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.lily_pad.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "sms" {
  api_id    = aws_apigatewayv2_api.lily_pad.id
  route_key = "POST /sms"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.lily_pad.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 10
    throttling_rate_limit  = 5
  }
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lily_pad.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.lily_pad.execution_arn}/*/*"
}
