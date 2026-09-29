terraform {
  required_version = ">= 1.11" # S3-native state locking (use_lockfile)

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    okta = {
      source  = "okta/okta"
      version = "~> 7.0"
    }
  }

  backend "s3" {
    bucket       = "lily-pad-terraform-state-us-west-2"
    key          = "lily-pad/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true # lock via a .tflock object so CI and laptop can't apply concurrently
  }
}

provider "aws" {
  region = var.aws_region
}
provider "okta" {
  org_name = "integrator-3224668" # non-admin host
  base_url = "okta.com"
  # client_id / private_key_id / private_key / scopes come from
  # OKTA_API_CLIENT_ID, OKTA_API_PRIVATE_KEY_ID, OKTA_API_PRIVATE_KEY, OKTA_API_SCOPES
}

# ── Secrets (SSM Parameter Store) ────────────────────────────────────────────
# /lily-pad/shortcuts-api-key (validated on POST /log) is a SecureString
# parameter created manually (see README). It is managed outside Terraform so
# its value never passes through terraform.tfvars or state; the Lambda reads it
# at runtime. GET /data is protected by Okta login instead of a secret.

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
# Zip lambda/build/ (produced by lambda/build.sh: handler.py, phrases.py, and
# pinned Linux wheels). Run build.sh before plan/apply. Output goes to
# terraform/ to keep it outside the source dir.

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/build"
  output_path = "${path.module}/lambda_package.zip"
}

resource "aws_lambda_function" "lily_pad" {
  function_name    = "lily-pad"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  memory_size      = 256
  timeout          = 10
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE   = aws_dynamodb_table.lily_events.name
      API_KEY_SSM_PATH = "/lily-pad/shortcuts-api-key"
      OKTA_CLIENT_ID   = okta_app_oauth.lily_pad_dashboard.client_id
      OKTA_ISSUER      = "https://integrator-3224668.okta.com"
      OKTA_JWKS_URL    = "https://integrator-3224668.okta.com/oauth2/v1/keys"
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]

  tags = {
    Project = "lily-pad"
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/lily-pad"
  retention_in_days = 30

  tags = {
    Project = "lily-pad"
  }
}

# ── API Gateway ───────────────────────────────────────────────────────────────

resource "aws_apigatewayv2_api" "lily_pad" {
  name          = "lily-pad"
  protocol_type = "HTTP"

  # The Authorization header makes dashboard fetches non-simple requests,
  # so the browser preflights them; HTTP APIs answer OPTIONS automatically
  # when this block is set. Only the CloudFront origin is allowed.
  cors_configuration {
    allow_origins = ["https://${aws_cloudfront_distribution.dashboard.domain_name}"]
    allow_methods = ["GET", "POST"]
    allow_headers = ["content-type", "x-api-key", "authorization"]
    max_age       = 3600
  }

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

resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/apigateway/lily-pad"
  retention_in_days = 30

  tags = {
    Project = "lily-pad"
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.lily_pad.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 10
    throttling_rate_limit  = 5
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format = jsonencode({
      requestId        = "$context.requestId"
      ip               = "$context.identity.sourceIp"
      requestTime      = "$context.requestTime"
      routeKey         = "$context.routeKey"
      status           = "$context.status"
      responseLength   = "$context.responseLength"
      integrationError = "$context.integrationErrorMessage"
    })
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

resource "aws_cloudfront_response_headers_policy" "dashboard" {
  name = "lily-pad-dashboard-security-headers"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    content_security_policy {
      # connect-src uses a region wildcard on purpose: referencing the API
      # endpoint here would create a dependency cycle (API CORS needs the
      # CloudFront domain, CloudFront needs this policy).
      content_security_policy = "default-src 'none'; script-src 'unsafe-inline' https://cdn.jsdelivr.net; style-src 'unsafe-inline'; img-src 'self'; connect-src https://*.execute-api.${var.aws_region}.amazonaws.com https://integrator-3224668.okta.com; base-uri 'none'; frame-ancestors 'none'"
      override                = true
    }
  }
}

resource "aws_cloudfront_distribution" "dashboard" {
  enabled             = true
  default_root_object = "public.html"

  origin {
    domain_name              = aws_s3_bucket.dashboard.bucket_regional_domain_name
    origin_id                = "s3-oac"
    origin_access_control_id = aws_cloudfront_origin_access_control.dashboard.id
  }

  default_cache_behavior {
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    target_origin_id           = "s3-oac"
    viewer_protocol_policy     = "redirect-to-https"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.dashboard.id

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

resource "aws_s3_bucket_server_side_encryption_configuration" "dashboard" {
  bucket = aws_s3_bucket.dashboard.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
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
      Sid       = "AllowCloudFrontOAC"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.dashboard.arn}/*"
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

locals {
  data_url = "${trimsuffix(aws_apigatewayv2_stage.default.invoke_url, "/")}/data"

  index_html = templatefile("${path.module}/../dashboard/index.html.tpl", {
    api_url        = local.data_url
    okta_client_id = okta_app_oauth.lily_pad_dashboard.client_id
  })

  public_html = templatefile("${path.module}/../dashboard/public.html.tpl", {
    api_url = local.data_url
  })
}

resource "aws_s3_object" "dashboard_html" {
  bucket        = aws_s3_bucket.dashboard.id
  key           = "index.html"
  content_type  = "text/html"
  content       = local.index_html
  etag          = md5(local.index_html)
  cache_control = "no-cache" # HTML is the entry point: always revalidate, so config baked into it (e.g. the Okta client ID) takes effect immediately

}

resource "aws_s3_object" "dashboard_html_public" {
  bucket        = aws_s3_bucket.dashboard.id
  key           = "public.html"
  content_type  = "text/html"
  content       = local.public_html
  etag          = md5(local.public_html)
  cache_control = "no-cache" # HTML is the entry point: always revalidate, so config baked into it (e.g. the Okta client ID) takes effect immediately
}
