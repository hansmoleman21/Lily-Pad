variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-west-2"
}

variable "twilio_account_sid" {
  description = "Twilio Account SID (used to validate inbound webhook signatures)"
  type        = string
  sensitive   = true
}

