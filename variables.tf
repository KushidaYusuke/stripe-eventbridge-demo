variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "ap-northeast-1"
}

variable "stripe_event_source_name_prefix" {
  description = "Prefix of the Stripe partner event source (e.g., aws.partner/stripe.com/<acct_id>/prod). Must match the source created when connecting Stripe to EventBridge."
  type        = string
}

variable "table_name" {
  description = "DynamoDB table name for storing Stripe events."
  type        = string
  default     = "stripe_webhooks"
}

variable "project_name" {
  description = "Base name used for created resources."
  type        = string
  default     = "stripe-eventbridge-demo"
}

variable "default_tags" {
  description = "Tags applied to all supported resources."
  type        = map(string)
  default = {
    Project = "stripe-eventbridge-demo"
  }
}
