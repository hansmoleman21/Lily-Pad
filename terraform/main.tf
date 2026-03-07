terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket  = "lily-pad-terraform-state-us-west-2"
    key     = "lily-pad/terraform.tfstate"
    region  = "us-west-2"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Secrets (SSM Parameter Store) ────────────────────────────────────────────
# Stored as SecureString (AES-256 encrypted at rest).
# The Lambda reads this path at cold start — the actual token never appears
# in the Lambda configuration or environment variables.

resource "aws_ssm_parameter" "shortcuts_api_key" {
  name  = "/lily-pad/shortcuts-api-key"
  type  = "SecureString"
  value = var.shortcuts_api_key
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
      DYNAMODB_TABLE   = aws_dynamodb_table.lily_events.name
      API_KEY_SSM_PATH = "/lily-pad/shortcuts-api-key"
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

resource "aws_apigatewayv2_route" "log" {
  api_id    = aws_apigatewayv2_api.lily_pad.id
  route_key = "POST /log"
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

# ── CloudFront HTTPS distribution ────────────────────────────────────────────

resource "aws_cloudfront_origin_access_control" "dashboard" {
  name                              = "lily-pad-dashboard"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "dashboard" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.dashboard.bucket_regional_domain_name
    origin_id                = "s3-oac"
    origin_access_control_id = aws_cloudfront_origin_access_control.dashboard.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-oac"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }


  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

# ── GET /data route ───────────────────────────────────────────────────────────

resource "aws_apigatewayv2_route" "data" {
  api_id    = aws_apigatewayv2_api.lily_pad.id
  route_key = "GET /data"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# ── Dashboard S3 Bucket ───────────────────────────────────────────────────────

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "dashboard" {
  bucket = "lily-pad-dashboard-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "dashboard" {
  bucket                  = aws_s3_bucket.dashboard.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "dashboard_cloudfront_oac" {
  bucket     = aws_s3_bucket.dashboard.id
  depends_on = [aws_s3_bucket_public_access_block.dashboard]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowCloudFrontOAC"
      Effect = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.dashboard.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.dashboard.arn
        }
      }
    }]
  })
}

resource "aws_s3_object" "dashboard_image" {
  bucket       = aws_s3_bucket.dashboard.id
  key          = "Lily-and-DC.PNG"
  source       = "${path.module}/../dashboard/Lily-and-DC.PNG"
  content_type = "image/png"
  etag         = filemd5("${path.module}/../dashboard/Lily-and-DC.PNG")
}

resource "aws_s3_object" "dashboard_html" {
  bucket       = aws_s3_bucket.dashboard.id
  key          = "index.html"
  content_type = "text/html"
  content      = templatefile("${path.module}/../dashboard/index.html.tpl", {
    api_url = "${trimsuffix(aws_apigatewayv2_stage.default.invoke_url, "/")}/data"
  })
  etag = md5(templatefile("${path.module}/../dashboard/index.html.tpl", {
    api_url = "${trimsuffix(aws_apigatewayv2_stage.default.invoke_url, "/")}/data"
  }))
}
