output "aws_region" {
  value = var.aws_region
}

output "data_bucket_name" {
  value = aws_s3_bucket.data.bucket
}

output "ecr_repository_url" {
  value = aws_ecr_repository.inference.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "ecs_task_definition_arn" {
  value = aws_ecs_task_definition.inference.arn
}

output "rds_endpoint" {
  value       = aws_db_instance.main.address
  description = "Private endpoint; reachable only from allowed VPC resources."
}

output "api_base_url" {
  value = aws_apigatewayv2_stage.default.invoke_url
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "cognito_app_client_id" {
  value = aws_cognito_user_pool_client.web_mobile.id
}

output "amplify_default_domain" {
  value       = var.enable_amplify ? aws_amplify_app.web[0].default_domain : null
  description = "Null until enable_amplify=true and a repository URL is supplied."
}

output "sns_alert_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "sagemaker_training_job_name" {
  value       = var.enable_sagemaker_training_job ? aws_sagemaker_training_job.kiln_model[0].training_job_name : null
  description = "Null unless the optional SageMaker training job is enabled."
}


output "agent_ecr_repository_url" { value = aws_ecr_repository.agents.repository_url }
output "agent_runtime_arn" {
  value = var.enable_agentcore ? aws_bedrockagentcore_agent_runtime.kilnwatch[0].agent_runtime_arn : null
}
output "agent_runtime_id" {
  value = var.enable_agentcore ? aws_bedrockagentcore_agent_runtime.kilnwatch[0].agent_runtime_id : null
}
output "agent_model_id" { value = var.agent_model_id }
