variable "aws_region" {
  description = "AWS region the main stack deploys into"
  type        = string
  default     = "us-west-2"
}

variable "github_repo" {
  description = "GitHub repository (owner/name) whose Actions runs may assume the CI roles"
  type        = string
  default     = "hansmoleman21/Lily-Pad"
}

variable "state_bucket" {
  description = "S3 bucket holding the main stack's Terraform state"
  type        = string
  default     = "lily-pad-terraform-state-us-west-2"
}

variable "state_key" {
  description = "Object key of the main stack's Terraform state"
  type        = string
  default     = "lily-pad/terraform.tfstate"
}
