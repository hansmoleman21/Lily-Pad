output "webhook_url" {
  description = "Paste this URL into Twilio as the SMS webhook (HTTP POST)"
  value       = "${aws_apigatewayv2_stage.default.invoke_url}/sms"
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.lily_events.name
}

output "lambda_function_name" {
  value = aws_lambda_function.lily_pad.function_name
}
