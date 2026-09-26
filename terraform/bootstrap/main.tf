# Bootstrap stack: the GitHub OIDC provider and the two roles CI assumes.
#
# Deliberately a separate root with its own state, applied only from a laptop
# with MFA (lily-pad-admin). If these roles lived in the main stack, CI could
# edit its own permissions: a merged PR could grant the apply role anything.
# CI has no access to this state, and an explicit Deny (below) stops it from
# modifying these roles even if a policy elsewhere were widened.
#
#   cd terraform/bootstrap && terraform init && terraform apply

terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "lily-pad-terraform-state-us-west-2"
    key          = "lily-pad/bootstrap.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = var.aws_region
  oidc_host  = "token.actions.githubusercontent.com"
}

# ── GitHub OIDC provider ─────────────────────────────────────────────────────
# GitHub mints a short-lived JWT per workflow run; AWS trusts it and returns
# temporary credentials. No AWS keys are stored in GitHub.

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://${local.oidc_host}"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"] # vestigial: AWS validates GitHub's certs natively

  tags = {
    Project = "lily-pad"
  }
}

# ── Trust policies ───────────────────────────────────────────────────────────
# Plan role: any branch or PR in the repo (the role is read-only).
# Apply role: only jobs running in the "production" GitHub Environment. A job
# that declares an environment gets sub = repo:<owner>/<repo>:environment:<name>,
# and the environment itself is restricted to main with a required reviewer.

data "aws_iam_policy_document" "ci_plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values   = ["repo:${var.github_repo}:*"]
    }
  }
}

data "aws_iam_policy_document" "ci_apply_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = ["repo:${var.github_repo}:environment:production"]
    }
  }
}

# ── Permissions: read (both roles) ───────────────────────────────────────────
# Everything terraform plan needs to refresh the main stack. Start narrow: if a
# plan fails with AccessDenied on a specific action, add exactly that action.

data "aws_iam_policy_document" "ci_read" {
  statement {
    sid       = "StateRead"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.state_bucket}"]
  }
  statement {
    sid       = "StateObjectRead"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/${var.state_key}"]
  }
  statement {
    sid = "DynamoDBTableMetadata"
    actions = [
      "dynamodb:DescribeTable",
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:ListTagsOfResource",
    ]
    resources = ["arn:aws:dynamodb:${local.region}:${local.account_id}:table/lily-events"]
  }
  statement {
    sid       = "LambdaRead"
    actions   = ["lambda:Get*", "lambda:List*"]
    resources = ["arn:aws:lambda:${local.region}:${local.account_id}:function:lily-pad"]
  }
  statement {
    sid     = "ApiGatewayRead"
    actions = ["apigateway:GET"]
    resources = [
      "arn:aws:apigateway:${local.region}::/apis",
      "arn:aws:apigateway:${local.region}::/apis/*",
      "arn:aws:apigateway:${local.region}::/tags/*",
    ]
  }
  statement {
    sid       = "LogsDescribe"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"] # DescribeLogGroups does not support resource-level scoping
  }
  statement {
    sid     = "LogsTags"
    actions = ["logs:ListTagsForResource", "logs:ListTagsLogGroup"]
    resources = [
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/lily-pad*",
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/apigateway/lily-pad*",
    ]
  }
  statement {
    sid     = "CloudFrontRead"
    actions = ["cloudfront:Get*", "cloudfront:List*"]
    resources = [
      "arn:aws:cloudfront::${local.account_id}:distribution/*",
      "arn:aws:cloudfront::${local.account_id}:origin-access-control/*",
      "arn:aws:cloudfront::${local.account_id}:response-headers-policy/*",
    ]
  }
  statement {
    sid     = "DashboardBucketRead"
    actions = ["s3:Get*", "s3:List*"]
    resources = [
      "arn:aws:s3:::lily-pad-dashboard-${local.account_id}",
      "arn:aws:s3:::lily-pad-dashboard-${local.account_id}/*",
    ]
  }
  statement {
    sid = "IamRead"
    actions = [
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/lily-pad-*"]
  }
}

# ── Permissions: write (apply role only) ─────────────────────────────────────
# Mirrors iam/lily-pad-admin-policy.json, minus its MFA condition (OIDC
# sessions never carry MFA; the trust policy's environment condition plus the
# required reviewer replace it), plus CloudFront/Logs/bucket-policy actions the
# main stack manages. No ssm:* — nothing in the main stack reads or writes SSM.

data "aws_iam_policy_document" "ci_write" {
  statement {
    sid       = "StateWrite"
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/${var.state_key}"]
  }
  statement {
    sid       = "StateLock"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.state_bucket}/${var.state_key}.tflock"]
  }
  statement {
    sid = "DynamoDBTableManagement"
    actions = [
      "dynamodb:CreateTable",
      "dynamodb:UpdateTable",
      "dynamodb:DeleteTable",
      "dynamodb:UpdateContinuousBackups",
      "dynamodb:UpdateTimeToLive",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
    ]
    resources = ["arn:aws:dynamodb:${local.region}:${local.account_id}:table/lily-events"]
  }
  statement {
    sid = "LambdaWrite"
    actions = [
      "lambda:CreateFunction",
      "lambda:UpdateFunctionCode",
      "lambda:UpdateFunctionConfiguration",
      "lambda:DeleteFunction",
      "lambda:AddPermission",
      "lambda:RemovePermission",
      "lambda:TagResource",
      "lambda:UntagResource",
    ]
    resources = ["arn:aws:lambda:${local.region}:${local.account_id}:function:lily-pad"]
  }
  statement {
    sid     = "ApiGatewayWrite"
    actions = ["apigateway:POST", "apigateway:PUT", "apigateway:PATCH", "apigateway:DELETE"]
    resources = [
      "arn:aws:apigateway:${local.region}::/apis",
      "arn:aws:apigateway:${local.region}::/apis/*",
      "arn:aws:apigateway:${local.region}::/tags/*",
    ]
  }
  statement {
    sid = "LogsWrite"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
      "logs:TagLogGroup",
      "logs:UntagLogGroup",
    ]
    resources = [
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/lambda/lily-pad*",
      "arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/apigateway/lily-pad*",
    ]
  }
  statement {
    # Required by API Gateway when configuring HTTP API access logging on a
    # stage. These actions don't support resource-level scoping.
    sid = "ApiGatewayAccessLogDelivery"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:PutResourcePolicy",
      "logs:DescribeResourcePolicies",
    ]
    resources = ["*"]
  }
  statement {
    sid = "CloudFrontWrite"
    actions = [
      "cloudfront:CreateDistribution",
      "cloudfront:UpdateDistribution",
      "cloudfront:DeleteDistribution",
      "cloudfront:TagResource",
      "cloudfront:UntagResource",
      "cloudfront:CreateOriginAccessControl",
      "cloudfront:UpdateOriginAccessControl",
      "cloudfront:DeleteOriginAccessControl",
      "cloudfront:CreateResponseHeadersPolicy",
      "cloudfront:UpdateResponseHeadersPolicy",
      "cloudfront:DeleteResponseHeadersPolicy",
    ]
    resources = [
      "arn:aws:cloudfront::${local.account_id}:distribution/*",
      "arn:aws:cloudfront::${local.account_id}:origin-access-control/*",
      "arn:aws:cloudfront::${local.account_id}:response-headers-policy/*",
    ]
  }
  statement {
    sid = "DashboardBucketWrite"
    actions = [
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:PutBucketPublicAccessBlock",
      "s3:PutEncryptionConfiguration",
      "s3:PutBucketTagging",
    ]
    resources = ["arn:aws:s3:::lily-pad-dashboard-${local.account_id}"]
  }
  statement {
    sid       = "DashboardObjectsWrite"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::lily-pad-dashboard-${local.account_id}/*"]
  }
  statement {
    sid = "IamRoleWrite"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/lily-pad-*"]
  }
  statement {
    # Only the one AWS-managed policy the main stack attaches — so CI can't
    # attach AdministratorAccess to a lily-pad-* role.
    sid       = "IamAttachBasicExecutionOnly"
    actions   = ["iam:AttachRolePolicy"]
    resources = ["arn:aws:iam::${local.account_id}:role/lily-pad-*"]
    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = ["arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"]
    }
  }
  statement {
    sid       = "IamPassLambdaRole"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${local.account_id}:role/lily-pad-lambda"]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["lambda.amazonaws.com"]
    }
  }
}

# ── Guardrails (both roles) ──────────────────────────────────────────────────
# Explicit Deny beats any Allow, including one added to these roles later.

data "aws_iam_policy_document" "ci_deny" {
  statement {
    # Terraform manages the table, never its contents (same rule as
    # lily-pad-admin): CI must not be able to read, write, or export events.
    sid    = "DenyDynamoDBItemAccess"
    effect = "Deny"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:BatchGetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
      "dynamodb:BatchWriteItem",
      "dynamodb:PartiQLSelect",
      "dynamodb:PartiQLInsert",
      "dynamodb:PartiQLUpdate",
      "dynamodb:PartiQLDelete",
      "dynamodb:ExportTableToPointInTime",
    ]
    resources = ["*"]
  }
  statement {
    # CI must never modify its own identity or trust.
    sid     = "DenyCiSelfModification"
    effect  = "Deny"
    actions = ["iam:*"]
    resources = [
      "arn:aws:iam::${local.account_id}:role/lily-pad-ci-*",
      aws_iam_openid_connect_provider.github.arn,
    ]
  }
}

# ── Roles ────────────────────────────────────────────────────────────────────

resource "aws_iam_role" "ci_plan" {
  name                 = "lily-pad-ci-plan"
  description          = "GitHub Actions: terraform plan (read-only), any branch/PR"
  assume_role_policy   = data.aws_iam_policy_document.ci_plan_trust.json
  max_session_duration = 3600

  tags = {
    Project = "lily-pad"
  }
}

resource "aws_iam_role_policy" "ci_plan_read" {
  name   = "lily-pad-ci-read"
  role   = aws_iam_role.ci_plan.id
  policy = data.aws_iam_policy_document.ci_read.json
}

resource "aws_iam_role_policy" "ci_plan_deny" {
  name   = "lily-pad-ci-deny"
  role   = aws_iam_role.ci_plan.id
  policy = data.aws_iam_policy_document.ci_deny.json
}

resource "aws_iam_role" "ci_apply" {
  name                 = "lily-pad-ci-apply"
  description          = "GitHub Actions: terraform apply, production environment only"
  assume_role_policy   = data.aws_iam_policy_document.ci_apply_trust.json
  max_session_duration = 3600

  tags = {
    Project = "lily-pad"
  }
}

resource "aws_iam_role_policy" "ci_apply_read" {
  name   = "lily-pad-ci-read"
  role   = aws_iam_role.ci_apply.id
  policy = data.aws_iam_policy_document.ci_read.json
}

resource "aws_iam_role_policy" "ci_apply_write" {
  name   = "lily-pad-ci-write"
  role   = aws_iam_role.ci_apply.id
  policy = data.aws_iam_policy_document.ci_write.json
}

resource "aws_iam_role_policy" "ci_apply_deny" {
  name   = "lily-pad-ci-deny"
  role   = aws_iam_role.ci_apply.id
  policy = data.aws_iam_policy_document.ci_deny.json
}
