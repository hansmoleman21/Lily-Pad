variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-2"
}

variable "shortcuts_api_key" {
  description = "API key for the Apple Shortcuts /log endpoint"
  type        = string
  sensitive   = true
}

