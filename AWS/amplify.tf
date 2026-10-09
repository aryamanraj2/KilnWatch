resource "aws_amplify_app" "web" {
  count        = var.enable_amplify ? 1 : 0
  name         = "${var.project_name}-web"
  repository   = var.frontend_repository_url
  access_token = var.frontend_access_token != "" ? var.frontend_access_token : null
  build_spec   = var.frontend_build_spec
  platform     = "WEB"

  environment_variables = {
    VITE_API_BASE_URL      = aws_apigatewayv2_stage.default.invoke_url
    VITE_COGNITO_USER_POOL = aws_cognito_user_pool.main.id
    VITE_COGNITO_CLIENT_ID = aws_cognito_user_pool_client.web_mobile.id
    VITE_AWS_REGION        = var.aws_region
  }

  lifecycle {
    precondition {
      condition     = var.frontend_repository_url != ""
      error_message = "Set frontend_repository_url before enabling Amplify."
    }
  }
}

resource "aws_amplify_branch" "web" {
  count             = var.enable_amplify ? 1 : 0
  app_id            = aws_amplify_app.web[0].id
  branch_name       = var.frontend_branch
  enable_auto_build = true
}
