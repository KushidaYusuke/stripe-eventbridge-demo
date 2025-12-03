output "event_bus_arn" {
  description = "ARN of the Stripe partner event bus."
  value       = aws_cloudwatch_event_bus.stripe.arn
}

output "event_rule_name" {
  description = "Name of the EventBridge rule routing Stripe events."
  value       = aws_cloudwatch_event_rule.stripe_events.name
}

output "lambda_function_name" {
  description = "Lambda function processing Stripe events."
  value       = aws_lambda_function.stripe_router.function_name
}

output "dynamodb_table_name" {
  description = "DynamoDB table where Stripe events are stored."
  value       = aws_dynamodb_table.webhooks.name
}
