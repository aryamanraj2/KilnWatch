resource "aws_lambda_function" "api" {
  function_name    = "${var.project_name}-api"
  role             = aws_iam_role.api_lambda.arn
  runtime          = "python3.12"
  architectures    = ["x86_64"]
  handler          = "api_handler.handler"
  filename         = "${path.module}/build/api_handler.zip"
  source_code_hash = filebase64sha256("${path.module}/build/api_handler.zip")
  timeout          = 15
  memory_size      = 256

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_HOST           = aws_db_instance.main.address
      DB_PORT           = tostring(aws_db_instance.main.port)
      DB_NAME           = var.db_name
      DB_CA_BUNDLE      = "/var/task/rds-ca.pem"
      COGNITO_CLIENT_ID = aws_cognito_user_pool_client.web_mobile.id
      DB_SECRET         = aws_secretsmanager_secret.registry_reader.arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.api_lambda_logs,
    aws_iam_role_policy_attachment.api_lambda_vpc,
    aws_iam_role_policy.api_lambda_secrets,
    aws_vpc_endpoint.secrets,
    aws_vpc_security_group_egress_rule.lambda_secrets,
    aws_vpc_security_group_egress_rule.lambda_postgres
  ]
}

resource "aws_cognito_user_pool" "main" {
  name                     = "${var.project_name}-users"
  auto_verified_attributes = ["email"]
  admin_create_user_config { allow_admin_create_user_only = true }
  schema {
    name                = "district"
    attribute_data_type = "String"
    mutable             = false
    required            = false
    string_attribute_constraints {
      min_length = 1
      max_length = 64
    }
  }
  password_policy {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }
}

resource "aws_cognito_user_pool_client" "web_mobile" {
  name                          = "${var.project_name}-web-mobile"
  user_pool_id                  = aws_cognito_user_pool.main.id
  generate_secret               = false
  read_attributes               = ["email", "email_verified", "custom:district"]
  write_attributes              = ["email"]
  explicit_auth_flows           = ["ALLOW_USER_SRP_AUTH", "ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
  prevent_user_existence_errors = "ENABLED"
  access_token_validity         = 60
  id_token_validity             = 60
  refresh_token_validity        = 30
  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }
}

resource "aws_apigatewayv2_api" "http" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
  cors_configuration {
    allow_origins = var.frontend_origin != "" ? [var.frontend_origin] : ["http://localhost:5173"]
    allow_methods = ["GET", "POST", "PATCH", "OPTIONS"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 300
  }
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.http.id
  name             = "${var.project_name}-cognito-authorizer"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  jwt_configuration {
    audience = [aws_cognito_user_pool_client.web_mobile.id]
    issuer   = "https://${aws_cognito_user_pool.main.endpoint}"
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_kilns" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "GET /kilns"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Public, no-login resident reads: flagged kilns only (SQL) and allowlisted fields (handler).
resource "aws_apigatewayv2_route" "get_public_kilns" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /public/kilns"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "get_public_kiln" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /public/kilns/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "get_kiln" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "GET /kilns/{id}"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_apigatewayv2_route" "get_health" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /health"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "post_jobs" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "POST /jobs"
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_cloudwatch_log_group" "api_lambda" {
  name              = "/aws/lambda/${var.project_name}-api"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_group" "api_gateway" {
  name              = "/aws/apigateway/${var.project_name}"
  retention_in_days = 14
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
  default_route_settings {
    throttling_rate_limit  = 50
    throttling_burst_limit = 100
  }
  # Unauthenticated, database-backed routes get a tighter limit. No Lambda reserved concurrency (account limit may be 10).
  dynamic "route_settings" {
    for_each = [aws_apigatewayv2_route.get_public_kilns.route_key, aws_apigatewayv2_route.get_public_kiln.route_key]
    content {
      route_key              = route_settings.value
      throttling_rate_limit  = 10
      throttling_burst_limit = 20
    }
  }
  # Phase 4A: the public, per-call-billed Ask route gets its own tighter limit (empty unless enable_assistant).
  dynamic "route_settings" {
    for_each = aws_apigatewayv2_route.ask[*].route_key
    content {
      route_key              = route_settings.value
      throttling_rate_limit  = 1
      throttling_burst_limit = 2
    }
  }
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gateway.arn
    format = jsonencode({
      requestId = "$context.requestId"
      routeKey  = "$context.routeKey"
      status    = "$context.status"
      sourceIp  = "$context.identity.sourceIp"
    })
  }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

resource "aws_iam_role_policy" "api_lambda_invoke_agentcore" {
  count = var.enable_agentcore ? 1 : 0
  name  = "${var.project_name}-api-invoke-agentcore"
  role  = aws_iam_role.api_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock-agentcore:InvokeAgentRuntime"]
      Resource = [aws_bedrockagentcore_agent_runtime.kilnwatch[0].agent_runtime_arn]
    }]
  })
}

resource "aws_cognito_user_group" "inspector" {
  name         = "inspector"
  user_pool_id = aws_cognito_user_pool.main.id
  description  = "District-scoped registry reads; membership assigned by an administrator."
}
