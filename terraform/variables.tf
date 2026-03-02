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

variable "twilio_auth_token" {
  description = "Twilio Auth Token (used to validate inbound webhook signatures)"
  type        = string
  sensitive   = true
}

variable "allowed_phone_numbers" {
  description = "Comma-separated list of E.164 phone numbers allowed to log events (e.g. +15555550100,+15555550101)"
  type        = string
  default     = ""
}
