data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "lily-pad-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = {
    Project = "lily-pad"
  }
}

# Basic Lambda execution (CloudWatch Logs)
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# DynamoDB read/write on the lily-events table only
data "aws_iam_policy_document" "dynamodb_access" {
  statement {
    actions   = ["dynamodb:PutItem", "dynamodb:Query"]
    resources = [aws_dynamodb_table.lily_events.arn]
  }
}

resource "aws_iam_role_policy" "dynamodb_access" {
  name   = "lily-pad-dynamodb"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.dynamodb_access.json
}

# SSM read access for the Twilio auth token (SecureString)
data "aws_iam_policy_document" "ssm_access" {
  statement {
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.twilio_auth_token.arn]
  }
}

resource "aws_iam_role_policy" "ssm_access" {
  name   = "lily-pad-ssm"
  role   = aws_iam_role.lambda_exec.id
  policy = data.aws_iam_policy_document.ssm_access.json
}
