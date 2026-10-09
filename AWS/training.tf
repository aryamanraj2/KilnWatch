data "aws_iam_policy_document" "sagemaker_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sagemaker_training" {
  count              = var.enable_sagemaker_training_job ? 1 : 0
  name               = "${var.project_name}-sagemaker-training"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume.json
}

resource "aws_iam_role_policy_attachment" "sagemaker_training_managed" {
  count      = var.enable_sagemaker_training_job ? 1 : 0
  role       = aws_iam_role.sagemaker_training[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_iam_role_policy" "sagemaker_s3" {
  count = var.enable_sagemaker_training_job ? 1 : 0
  name  = "${var.project_name}-sagemaker-s3"
  role  = aws_iam_role.sagemaker_training[0].id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect   = "Allow",
      Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
      Resource = [aws_s3_bucket.data.arn, "${aws_s3_bucket.data.arn}/*"]
    }]
  })
}

resource "aws_sagemaker_training_job" "kiln_model" {
  count = var.enable_sagemaker_training_job ? 1 : 0

  training_job_name = "${var.project_name}-${var.environment}-training"
  role_arn          = aws_iam_role.sagemaker_training[0].arn

  algorithm_specification {
    training_image      = var.sagemaker_training_image_uri
    training_input_mode = "File"
  }

  input_data_config {
    channel_name = "training"
    data_source {
      s3_data_source {
        s3_data_type              = "S3Prefix"
        s3_uri                    = "s3://${aws_s3_bucket.data.bucket}/dataset/"
        s3_data_distribution_type = "FullyReplicated"
      }
    }
  }

  output_data_config {
    s3_output_path = "s3://${aws_s3_bucket.data.bucket}/training-output/"
  }

  resource_config {
    instance_type     = var.sagemaker_training_instance_type
    instance_count    = 1
    volume_size_in_gb = 50
  }

  stopping_condition {
    max_runtime_in_seconds = var.sagemaker_max_runtime_seconds
  }

  lifecycle {
    precondition {
      condition     = var.sagemaker_training_image_uri != ""
      error_message = "Set sagemaker_training_image_uri to your compatible custom training image before enabling the training job."
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.sagemaker_training_managed[0],
    aws_iam_role_policy.sagemaker_s3[0]
  ]
}
