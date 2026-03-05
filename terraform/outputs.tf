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
