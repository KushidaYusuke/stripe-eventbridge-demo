terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.65"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# Discover the Stripe partner event source that must already exist once you
# connect Stripe to EventBridge in the Stripe Dashboard.
data "aws_cloudwatch_event_source" "stripe" {
  name_prefix = var.stripe_event_source_name_prefix
}

# Partner event bus must use the exact partner source name.
resource "aws_cloudwatch_event_bus" "stripe" {
  name              = data.aws_cloudwatch_event_source.stripe.name
  event_source_name = data.aws_cloudwatch_event_source.stripe.name
}

resource "aws_dynamodb_table" "webhooks" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"

  hash_key = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }

  tags = var.default_tags
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.default_tags
}

data "aws_iam_policy_document" "lambda_policy" {
  statement {
    sid = "DynamoWrite"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:DescribeTable"
    ]
    resources = [aws_dynamodb_table.webhooks.arn]
  }

  statement {
    sid = "CloudWatchLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"]
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name   = "${var.project_name}-lambda-policy"
  policy = data.aws_iam_policy_document.lambda_policy.json
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

resource "aws_lambda_function" "stripe_router" {
  function_name = "${var.project_name}-handler"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.14"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.webhooks.name
    }
  }

  tags = var.default_tags
}

resource "aws_cloudwatch_event_rule" "stripe_events" {
  name           = "${var.project_name}-rule"
  description    = "Route Stripe partner events to Lambda"
  event_bus_name = aws_cloudwatch_event_bus.stripe.name

  event_pattern = jsonencode({
    "source" : [data.aws_cloudwatch_event_source.stripe.name],
    "detail-type" : [
      "customer.subscription.created",
      "customer.subscription.updated",
      "invoice.created",
      "invoice.payment_succeeded",
      "invoice.payment_failed",
      "customer.subscription.deleted"
    ]
  })

  tags = var.default_tags
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule           = aws_cloudwatch_event_rule.stripe_events.name
  event_bus_name = aws_cloudwatch_event_rule.stripe_events.event_bus_name
  arn            = aws_lambda_function.stripe_router.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.stripe_router.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.stripe_events.arn
}
