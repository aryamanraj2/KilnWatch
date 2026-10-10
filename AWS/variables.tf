variable "aws_region" {
  description = "Primary region for API, registry and app data (Mumbai, near NCR inspectors). Offline detection still reads Earth Search imagery in us-west-2."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  type    = string
  default = "kilnwatch"
}

variable "environment" {
  type    = string
  default = "hackathon"
}

variable "bucket_name_prefix" {
  description = "Globally unique lowercase prefix; Terraform adds a random suffix."
  type        = string
  default     = "kilnwatch"
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.40.1.0/24", "10.40.2.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.40.11.0/24", "10.40.12.0/24"]
}

variable "db_name" {
  type    = string
  default = "kilnwatch"
}

variable "db_username" {
  type    = string
  default = "kilnwatch_admin"
}

variable "db_instance_class" {
  description = "Use a small instance for a short prototype; verify current regional pricing."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

variable "ecs_task_cpu" {
  type    = number
  default = 512
}

variable "ecs_task_memory" {
  type    = number
  default = 1024
}

variable "enable_amplify" {
  description = "Enable only after a Git repository URL is available."
  type        = bool
  default     = false
}

variable "frontend_repository_url" {
  description = "Placeholder: HTTPS Git repository URL for the web frontend."
  type        = string
  default     = ""
}

variable "frontend_branch" {
  type    = string
  default = "main"
}

variable "frontend_access_token" {
  description = "Optional Git provider token where required. Prefer a secret store/CI variable; never commit it."
  type        = string
  sensitive   = true
  default     = ""
}

variable "frontend_build_spec" {
  description = "Adjust to your frontend framework/build output."
  type        = string
  default     = "version: 1\nfrontend:\n  phases:\n    preBuild:\n      commands:\n        - npm ci\n    build:\n      commands:\n        - npm run build\n  artifacts:\n    baseDirectory: dist\n    files:\n      - '**/*'\n  cache:\n    paths:\n      - node_modules/**/*\n"
}

variable "alert_email" {
  description = "Optional email for SNS alarm notifications. Confirm subscription from the email."
  type        = string
  default     = ""
}

variable "create_demo_ecs_service" {
  description = "Usually false for a batch inference task launched by Step Functions. Turn on only if you build a long-running HTTP inference server."
  type        = bool
  default     = false
}

variable "create_bedrock_agent" {
  description = "Bedrock agent resources are left out of the default scaffold until prompts, action groups, and model access are decided."
  type        = bool
  default     = false
}


variable "enable_sagemaker_training_job" {
  description = "Enable only after uploading the dataset and building a compatible custom training container."
  type        = bool
  default     = false
}

variable "sagemaker_training_image_uri" {
  description = "ECR URI for your YOLO-OBB training container. Required only when enabling the training job."
  type        = string
  default     = ""
}

variable "sagemaker_training_instance_type" {
  description = "Confirm regional availability and pricing before enabling."
  type        = string
  default     = "ml.m5.large"
}

variable "sagemaker_max_runtime_seconds" {
  type    = number
  default = 3600
}

# Amazon Bedrock AgentCore / Strands settings
variable "agent_image_tag" {
  type    = string
  default = "v1"
}

variable "agent_model_id" {
  description = "Claude Sonnet 4.6 global inference profile; verify account access, regional availability and pricing."
  type        = string
  default     = "global.anthropic.claude-sonnet-4-6"
}

variable "agent_temperature" {
  type    = number
  default = 0.1
}

variable "agentcore_idle_timeout_seconds" {
  type    = number
  default = 300
}

variable "agentcore_max_lifetime_seconds" {
  type    = number
  default = 1800
}

variable "enable_agentcore" {
  description = "Enable after the Strands container image is pushed to ECR."
  type        = bool
  default     = false
}

variable "frontend_origin" {
  description = "Exact deployed web origin for API CORS, e.g. https://main.xxxxxx.amplifyapp.com. Use a local dev origin only while testing."
  type        = string
  default     = ""
}

variable "inference_image_tag" {
  description = "Tag to deploy from the inference ECR repository after the team's container is ready."
  type        = string
  default     = "bootstrap"
}

variable "create_registry_runner" {
  description = "Optional temporary SSM runner for private DB migration/import; review before enabling. No inbound ports."
  type        = bool
  default     = false
}

variable "enable_assistant" {
  description = "Phase 4A public POST /ask assistant Lambda, counter table and route. Build AWS/build/assistant.zip first."
  type        = bool
  default     = false
}

variable "assistant_model_id" {
  description = "Bedrock cross-region inference profile ID for the assistant (Phase 4A preflight recommendation)."
  type        = string
  default     = "global.amazon.nova-2-lite-v1:0"
}

variable "assistant_daily_cap" {
  description = "Hard cap on Ask questions per UTC day across all callers."
  type        = number
  default     = 50
  validation {
    condition     = var.assistant_daily_cap >= 1 && floor(var.assistant_daily_cap) == var.assistant_daily_cap
    error_message = "assistant_daily_cap must be a positive integer."
  }
}

variable "assistant_bedrock_role_arn" {
  description = "Optional IAM role in another AWS account that the assistant assumes to call Bedrock. Empty calls Bedrock in this account. Set it only in the ignored terraform.tfvars."
  type        = string
  default     = ""
  validation {
    condition     = var.assistant_bedrock_role_arn == "" || can(regex("^arn:aws:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.assistant_bedrock_role_arn))
    error_message = "assistant_bedrock_role_arn must be empty or an IAM role ARN."
  }
}

variable "assistant_bedrock_region" {
  description = "Optional region for the assistant's Bedrock calls. Empty uses the Lambda's region."
  type        = string
  default     = ""
}

variable "evidence_cdn_account" {
  description = "Account that hosts the evidence CloudFront distribution: \"main\", or \"second\" (via the aws.cdn provider) while the main account cannot create CloudFront."
  type        = string
  default     = "main"
  validation {
    condition     = contains(["main", "second"], var.evidence_cdn_account)
    error_message = "evidence_cdn_account must be \"main\" or \"second\"."
  }
}

variable "cdn_profile" {
  description = "Optional AWS config profile for the aws.cdn provider. Empty uses the default credential chain. Set it only in the ignored terraform.tfvars."
  type        = string
  default     = ""
}
