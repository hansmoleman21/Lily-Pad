output "plan_role_arn" {
  description = "Read-only role for terraform plan (any branch/PR). Set as repo variable AWS_PLAN_ROLE_ARN."
  value       = aws_iam_role.ci_plan.arn
}

output "apply_role_arn" {
  description = "Role for terraform apply (production environment only). Set as repo variable AWS_APPLY_ROLE_ARN."
  value       = aws_iam_role.ci_apply.arn
}
