# Phase 4A "Ask": public POST /ask, one small Lambda outside the VPC that reads only the public API.
# Everything here is off unless enable_assistant = true. Build the ZIP first: python AWS/scripts/package_assistant.py

locals {
  assistant = var.enable_assistant ? 1 : 0
}

# The model must be a cross-region inference profile (Nova 2 Lite and Nova Pro are only invocable that way in ap-south-1).
# Invoking through a profile needs bedrock:InvokeModel on the profile ARN *and* on the foundation-model ARN in
# every destination region the profile may route to (for a global profile that includes the region-less
# arn:aws:bedrock:::foundation-model/... ARN), so all of them are read from the profile itself.
data "aws_bedrock_inference_profile" "assistant" {
  count                = local.assistant
  inference_profile_id = var.assistant_model_id
}

resource "aws_dynamodb_table" "assistant_counter" {
  count        = local.assistant
  name         = "${var.project_name}-assistant-daily"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "day"

  attribute {
    name = "day"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  # Encrypted at rest with the AWS-owned key (DynamoDB default). No streams.
  server_side_encryption {
    enabled = false
  }
}

resource "aws_cloudwatch_log_group" "assistant" {
  count             = local.assistant
  name              = "/aws/lambda/${var.project_name}-assistant"
  retention_in_days = 14
}

resource "aws_iam_role" "assistant" {
  count              = local.assistant
  name               = "${var.project_name}-assistant-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "assistant" {
  count = local.assistant
  name  = "${var.project_name}-assistant"
  role  = aws_iam_role.assistant[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.assistant[0].arn}:*"]
      },
      {
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = concat([data.aws_bedrock_inference_profile.assistant[0].inference_profile_arn],
        data.aws_bedrock_inference_profile.assistant[0].models[*].model_arn)
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = [aws_dynamodb_table.assistant_counter[0].arn]
      }
      ], var.assistant_bedrock_role_arn == "" ? [] : [
      {
        # Bedrock through a role in another account while this account's Bedrock is blocked.
        # The same-account statement above stays, so switching back needs no IAM change.
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = [var.assistant_bedrock_role_arn]
      }
    ])
  })
}

resource "aws_lambda_function" "assistant" {
  count         = local.assistant
  function_name = "${var.project_name}-assistant"
  role          = aws_iam_role.assistant[0].arn
  runtime       = "python3.12"
  architectures = ["x86_64"]
  handler       = "handler.handler"
  filename      = "${path.module}/build/assistant.zip"
  # fileexists keeps validate/plan working with enable_assistant=false and no ZIP built.
  source_code_hash = fileexists("${path.module}/build/assistant.zip") ? filebase64sha256("${path.module}/build/assistant.zip") : null
  timeout          = 28 # the HTTP API integration times out at 30 s
  memory_size      = 256

  # No vpc_config: reads only the public API over HTTPS; never RDS or Secrets Manager.
  environment {
    variables = merge({
      PUBLIC_API_BASE_URL = aws_apigatewayv2_api.http.api_endpoint
      MODEL_ID            = var.assistant_model_id
      DAILY_CAP           = tostring(var.assistant_daily_cap)
      COUNTER_TABLE       = aws_dynamodb_table.assistant_counter[0].name
      },
      var.assistant_bedrock_role_arn == "" ? {} : { BEDROCK_ROLE_ARN = var.assistant_bedrock_role_arn },
    var.assistant_bedrock_region == "" ? {} : { BEDROCK_REGION = var.assistant_bedrock_region })
  }

  depends_on = [aws_cloudwatch_log_group.assistant, aws_iam_role_policy.assistant]
}

resource "aws_apigatewayv2_integration" "assistant" {
  count                  = local.assistant
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.assistant[0].invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# Public on purpose (no app sign-in until Phase 5). Stage throttling (1/s, burst 2) and the daily cap protect it.
resource "aws_apigatewayv2_route" "ask" {
  count     = local.assistant
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /ask"
  target    = "integrations/${aws_apigatewayv2_integration.assistant[0].id}"
}

resource "aws_lambda_permission" "assistant" {
  count         = local.assistant
  statement_id  = "AllowApiGatewayInvokeAsk"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.assistant[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/POST/ask"
}
