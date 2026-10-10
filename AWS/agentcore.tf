resource "aws_ecr_repository" "agents" {
  name                 = "${var.project_name}-strands-agents"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_lifecycle_policy" "agents" {
  repository = aws_ecr_repository.agents.name
  policy = jsonencode({ rules = [{
    rulePriority = 1
    description  = "Keep latest 10 agent images"
    selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 10 }
    action       = { type = "expire" }
  }] })
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_iam_policy_document" "agentcore_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock-agentcore.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "agentcore_runtime" {
  name               = "${var.project_name}-agentcore-runtime"
  assume_role_policy = data.aws_iam_policy_document.agentcore_assume.json
}

resource "aws_iam_role_policy" "agentcore_ecr" {
  name = "${var.project_name}-agentcore-ecr-pull"
  role = aws_iam_role.agentcore_runtime.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      { Effect = "Allow", Action = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"], Resource = aws_ecr_repository.agents.arn }
    ]
  })
}

resource "aws_iam_role_policy" "agentcore_invoke_bedrock" {
  name = "${var.project_name}-invoke-bedrock-model"
  role = aws_iam_role.agentcore_runtime.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
      Resource = [
        "arn:${data.aws_partition.current.partition}:bedrock:*::foundation-model/*",
        "arn:${data.aws_partition.current.partition}:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy" "agentcore_logs" {
  name = "${var.project_name}-agentcore-logs"
  role = aws_iam_role.agentcore_runtime.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
      Resource = "*"
    }]
  })
}

resource "aws_bedrockagentcore_agent_runtime" "kilnwatch" {
  count              = var.enable_agentcore ? 1 : 0
  agent_runtime_name = "KilnWatchStrands"
  description        = "KilnWatch evidence, inspection triage and resident information assistant behaviours."
  role_arn           = aws_iam_role.agentcore_runtime.arn
  agent_runtime_artifact {
    container_configuration {
      container_uri = "${aws_ecr_repository.agents.repository_url}:${var.agent_image_tag}"
    }
  }
  network_configuration { network_mode = "PUBLIC" }
  environment_variables = {
    AWS_REGION            = var.aws_region
    KILNWATCH_MODEL_ID    = var.agent_model_id
    KILNWATCH_TEMPERATURE = tostring(var.agent_temperature)
    LOG_LEVEL             = "INFO"
  }
  lifecycle_configuration {
    idle_runtime_session_timeout = var.agentcore_idle_timeout_seconds
    max_lifetime                 = var.agentcore_max_lifetime_seconds
  }
  depends_on = [
    aws_iam_role_policy.agentcore_ecr,
    aws_iam_role_policy.agentcore_invoke_bedrock,
    aws_iam_role_policy.agentcore_logs
  ]
}
