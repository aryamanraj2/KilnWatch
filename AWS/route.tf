# P1 route planning: public POST /routes/plan, one small Lambda outside the VPC that reads only the public API and
# calls Amazon Location Routes (Core tier: Car, no tolls). Off unless enable_route_planner = true. It shares the
# assistant's counter table under its own key prefix (route#YYYY-MM-DD), so it also needs enable_assistant.
# Build the ZIP first: python AWS/scripts/package_route.py

locals {
  route = var.enable_route_planner && var.enable_assistant ? 1 : 0
}

resource "aws_cloudwatch_log_group" "route" {
  count             = local.route
  name              = "/aws/lambda/${var.project_name}-route"
  retention_in_days = 14
}

resource "aws_iam_role" "route" {
  count              = local.route
  name               = "${var.project_name}-route-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "route" {
  count = local.route
  name  = "${var.project_name}-route"
  role  = aws_iam_role.route[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.route[0].arn}:*"]
      },
      {
        # Only the route counter items, never the assistant's.
        Effect    = "Allow"
        Action    = ["dynamodb:UpdateItem"]
        Resource  = [aws_dynamodb_table.assistant_counter[0].arn]
        Condition = { "ForAllValues:StringLike" = { "dynamodb:LeadingKeys" = ["route#*"] } }
      },
      {
        Effect   = "Allow"
        Action   = ["geo-routes:CalculateRouteMatrix", "geo-routes:CalculateRoutes"]
        Resource = ["arn:${data.aws_partition.current.partition}:geo-routes:${var.aws_region}::provider/default"]
      }
    ]
  })
}

resource "aws_lambda_function" "route" {
  count         = local.route
  function_name = "${var.project_name}-route"
  role          = aws_iam_role.route[0].arn
  runtime       = "python3.12"
  architectures = ["x86_64"]
  handler       = "route_handler.handler"
  filename      = "${path.module}/build/route.zip"
  # fileexists keeps validate/plan working with enable_route_planner=false and no ZIP built.
  source_code_hash = fileexists("${path.module}/build/route.zip") ? filebase64sha256("${path.module}/build/route.zip") : null
  timeout          = 15
  memory_size      = 256

  # No vpc_config: reads only the public API over HTTPS and calls Amazon Location; never RDS or Secrets Manager.
  environment {
    variables = {
      PUBLIC_API_BASE_URL = aws_apigatewayv2_api.http.api_endpoint
      DAILY_CAP           = tostring(var.route_daily_cap)
      COUNTER_TABLE       = aws_dynamodb_table.assistant_counter[0].name
    }
  }

  depends_on = [aws_cloudwatch_log_group.route, aws_iam_role_policy.route]
}

resource "aws_apigatewayv2_integration" "route" {
  count                  = local.route
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.route[0].invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

# Public on purpose, like /ask. Stage throttling (1/s, burst 2) and the daily cap protect it.
resource "aws_apigatewayv2_route" "route_plan" {
  count     = local.route
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /routes/plan"
  target    = "integrations/${aws_apigatewayv2_integration.route[0].id}"
}

resource "aws_lambda_permission" "route" {
  count         = local.route
  statement_id  = "AllowApiGatewayInvokeRoutePlan"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.route[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/POST/routes/plan"
}
