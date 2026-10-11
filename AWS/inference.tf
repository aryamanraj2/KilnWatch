# Detector image build (prompts 38/38b). The main account's CodeBuild quota is 0, so the image is
# built by CodeBuild in the second account (aws.cdn) from a source zip in a small bucket there, and
# pushed into the main account's inference ECR repo. The repository policy below is the only
# cross-account write path. Runs stay in the main account (compute.tf, workflow.tf).

resource "aws_s3_bucket" "build_source" {
  provider      = aws.cdn
  count         = var.enable_model_pipeline ? 1 : 0
  bucket_prefix = "${var.project_name}-build-"
  force_destroy = true # Holds only build zips that expire after 7 days.
}

resource "aws_s3_bucket_public_access_block" "build_source" {
  provider                = aws.cdn
  count                   = var.enable_model_pipeline ? 1 : 0
  bucket                  = aws_s3_bucket.build_source[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "build_source" {
  provider = aws.cdn
  count    = var.enable_model_pipeline ? 1 : 0
  bucket   = aws_s3_bucket.build_source[0].id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "build_source" {
  provider = aws.cdn
  count    = var.enable_model_pipeline ? 1 : 0
  bucket   = aws_s3_bucket.build_source[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "build_source" {
  provider = aws.cdn
  count    = var.enable_model_pipeline ? 1 : 0
  bucket   = aws_s3_bucket.build_source[0].id
  rule {
    id     = "expire-build-zips"
    status = "Enabled"
    filter {}
    expiration { days = 7 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}

resource "aws_cloudwatch_log_group" "inference_build" {
  provider          = aws.cdn
  count             = var.enable_model_pipeline ? 1 : 0
  name              = "/aws/codebuild/${var.project_name}-inference-build"
  retention_in_days = 14
}

resource "aws_iam_role" "inference_build" {
  provider = aws.cdn
  count    = var.enable_model_pipeline ? 1 : 0
  name     = "${var.project_name}-inference-build"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "inference_build" {
  provider = aws.cdn
  count    = var.enable_model_pipeline ? 1 : 0
  name     = "${var.project_name}-inference-build"
  role     = aws_iam_role.inference_build[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadBuildSource"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${aws_s3_bucket.build_source[0].arn}/build/*"
      },
      {
        Sid      = "OwnLogGroup"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.inference_build[0].arn}:*"
      },
      {
        Sid      = "EcrToken"
        Effect   = "Allow"
        Action   = "ecr:GetAuthorizationToken"
        Resource = "*"
      },
      {
        Sid    = "PushInferenceRepo"
        Effect = "Allow"
        Action = ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage"]
        Resource = aws_ecr_repository.inference.arn
      }
    ]
  })
}

resource "aws_codebuild_project" "inference" {
  provider      = aws.cdn
  count         = var.enable_model_pipeline ? 1 : 0
  name          = "${var.project_name}-inference-build"
  service_role  = aws_iam_role.inference_build[0].arn
  build_timeout = 45

  source {
    type      = "S3"
    location  = "${aws_s3_bucket.build_source[0].id}/build/m0/source.zip"
    buildspec = "buildspec.yml"
  }

  artifacts { type = "NO_ARTIFACTS" }

  environment {
    type            = "ARM_CONTAINER"
    compute_type    = "BUILD_GENERAL1_MEDIUM"
    image           = "aws/codebuild/amazonlinux-aarch64-standard:3.0"
    privileged_mode = true

    environment_variable {
      name  = "ECR_REGISTRY"
      value = split("/", aws_ecr_repository.inference.repository_url)[0]
    }
    environment_variable {
      name  = "ECR_REPOSITORY"
      value = aws_ecr_repository.inference.name
    }
    environment_variable {
      name  = "ECR_REGION"
      value = var.aws_region
    }
  }

  logs_config {
    cloudwatch_logs { group_name = aws_cloudwatch_log_group.inference_build[0].name }
  }
}

# Main account: only the second-account build role may push to the inference repo.
resource "aws_ecr_repository_policy" "inference" {
  count      = var.enable_model_pipeline ? 1 : 0
  repository = aws_ecr_repository.inference.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "SecondAccountBuildPush"
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.inference_build[0].arn }
      Action = ["ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload", "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload", "ecr:PutImage", "ecr:BatchGetImage"]
    }]
  })
}
