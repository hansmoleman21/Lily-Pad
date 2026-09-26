variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-2"
}

variable "okta_dashboard_client_id" {
  description = "Client ID of the lily-pad-dashboard Okta OIDC app"
  type        = string
}