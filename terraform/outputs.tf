output "log_url" {
  description = "Use this URL as the endpoint in your Apple Shortcuts action (HTTP POST)"
  value       = "${trimsuffix(aws_apigatewayv2_stage.default.invoke_url, "/")}/log"
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.lily_events.name
}

output "lambda_function_name" {
  value = aws_lambda_function.lily_pad.function_name
}

output "dashboard_url" {
  description = "HTTPS URL of the public dashboard (no notes) — safe to share; also the CloudFront root"
  value       = "https://${aws_cloudfront_distribution.dashboard.domain_name}"
}

output "private_dashboard_url" {
  description = "Unguessable URL of the private dashboard (notes/medicine/weight) — bookmark it, don't share it. Retrieve with: terraform output -raw private_dashboard_url"
  value       = "https://${aws_cloudfront_distribution.dashboard.domain_name}/${local.private_page_key}"
  sensitive   = true
}
