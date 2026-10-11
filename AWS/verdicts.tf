variable "enable_verdicts" {
  description = "Enable the public demo verdict endpoint. Build the ZIP before enabling."
  type        = bool
  default     = false
}

locals {
  verdicts = var.enable_verdicts ? 1 : 0
}

resource "aws_secretsmanager_secret" "verdicts" {
  count                   = local.verdicts
  name                    = "${var.project_name}/verdicts-db"
  description             = "Dedicated verdict writer login, provisioned only through the runner."
  recovery_window_in_days = 7
}

resource "aws_cloudwatch_log_group" "verdicts" {
  count             = local.verdicts
  name              = "/aws/lambda/${var.project_name}-verdicts"
  retention_in_days = 14
}

resource "aws_iam_role" "verdicts" {
  count              = local.verdicts
  name               = "${var.project_name}-verdicts-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "verdicts" {
  count = local.verdicts
  name  = "${var.project_name}-verdicts"
  role  = aws_iam_role.verdicts[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["${aws_cloudwatch_log_group.verdicts[0].arn}:*"]
      },
      {
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = [aws_secretsmanager_secret.verdicts[0].arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = ["${aws_s3_bucket.data.arn}/verdicts/*"]
      },
      {
        Effect = "Allow"
        Action = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DescribeSubnets",
        "ec2:DeleteNetworkInterface", "ec2:AssignPrivateIpAddresses", "ec2:UnassignPrivateIpAddresses"]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_lambda_function" "verdicts" {
  count            = local.verdicts
  function_name    = "${var.project_name}-verdicts"
  role             = aws_iam_role.verdicts[0].arn
  runtime          = "python3.12"
  architectures    = ["x86_64"]
  handler          = "verdicts.handler.handler"
  filename         = "${path.module}/build/verdicts.zip"
  source_code_hash = fileexists("${path.module}/build/verdicts.zip") ? filebase64sha256("${path.module}/build/verdicts.zip") : null
  timeout          = 15
  memory_size      = 256
  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }
  environment {
    variables = {
      DB_HOST      = aws_db_instance.main.address
      DB_PORT      = tostring(aws_db_instance.main.port)
      DB_NAME      = var.db_name
      DB_CA_BUNDLE = "/var/task/rds-ca.pem"
      DB_SECRET    = aws_secretsmanager_secret.verdicts[0].arn
      DATA_BUCKET  = aws_s3_bucket.data.id
    }
  }
  depends_on = [aws_iam_role_policy.verdicts, aws_cloudwatch_log_group.verdicts,
    aws_vpc_endpoint.secrets, aws_vpc_security_group_egress_rule.lambda_secrets,
  aws_vpc_security_group_egress_rule.lambda_postgres]
}

resource "aws_apigatewayv2_integration" "verdicts" {
  count                  = local.verdicts
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.verdicts[0].invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "verdicts" {
  count              = local.verdicts
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "POST /verdicts"
  target             = "integrations/${aws_apigatewayv2_integration.verdicts[0].id}"
  authorization_type = "NONE"
}

resource "aws_lambda_permission" "verdicts" {
  count         = local.verdicts
  statement_id  = "AllowVerdictsApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.verdicts[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/POST/verdicts"
}

variable "enable_requests" {
  description = "Enable public anonymous inspection requests using the existing verdicts writer."
  type        = bool
  default     = false
}

# Deployment pending: prompt 43 needs explicit approval for the additional invocation permission.
resource "aws_apigatewayv2_route" "requests" {
  count              = var.enable_requests ? 1 : 0
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "POST /requests"
  target             = "integrations/${aws_apigatewayv2_integration.verdicts[0].id}"
  authorization_type = "NONE"
  lifecycle {
    precondition {
      condition     = var.enable_verdicts
      error_message = "Inspection requests require the existing verdicts Lambda and integration."
    }
  }
}

resource "aws_lambda_permission" "requests" {
  count         = var.enable_requests ? 1 : 0
  statement_id  = "AllowRequestsApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.verdicts[0].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/POST/requests"
}
