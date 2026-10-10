resource "aws_cloudfront_origin_access_control" "evidence" {
  name                              = "${var.project_name}-evidence"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "evidence" {
  count       = var.evidence_cdn_account == "main" ? 1 : 0
  enabled     = true
  comment     = "Publishable satellite PNGs only; model exports and field photos remain private."
  price_class = "PriceClass_200"
  origin {
    domain_name              = aws_s3_bucket.data.bucket_regional_domain_name
    origin_id                = "satellite-evidence"
    origin_access_control_id = aws_cloudfront_origin_access_control.evidence.id
  }
  default_cache_behavior {
    target_origin_id       = "satellite-evidence"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }
  restrictions {
    geo_restriction { restriction_type = "none" }
  }
  viewer_certificate { cloudfront_default_certificate = true }
  custom_error_response {
    error_code            = 403
    error_caching_min_ttl = 0
  }
}

# Second-account CDN while the main account cannot create CloudFront. The origin stays the
# main account's private bucket; only the bucket policy below grants this distribution access.
resource "aws_cloudfront_origin_access_control" "evidence_cdn" {
  provider                          = aws.cdn
  count                             = var.evidence_cdn_account == "second" ? 1 : 0
  name                              = "${var.project_name}-evidence"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "evidence_cdn" {
  provider    = aws.cdn
  count       = var.evidence_cdn_account == "second" ? 1 : 0
  enabled     = true
  comment     = "Second-account CDN for publishable satellite PNGs only; origin bucket stays private in the main account."
  price_class = "PriceClass_200"
  origin {
    domain_name              = aws_s3_bucket.data.bucket_regional_domain_name
    origin_id                = "satellite-evidence"
    origin_access_control_id = aws_cloudfront_origin_access_control.evidence_cdn[0].id
  }
  default_cache_behavior {
    target_origin_id       = "satellite-evidence"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }
  restrictions {
    geo_restriction { restriction_type = "none" }
  }
  viewer_certificate { cloudfront_default_certificate = true }
  custom_error_response {
    error_code            = 403
    error_caching_min_ttl = 0
  }
}

locals {
  evidence_distribution = var.evidence_cdn_account == "main" ? aws_cloudfront_distribution.evidence[0] : aws_cloudfront_distribution.evidence_cdn[0]
}

resource "aws_s3_bucket_policy" "evidence" {
  bucket = aws_s3_bucket.data.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "CloudFrontPublishableSatelliteEvidenceOnly"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.data.arn}/evidence/*.png"
      Condition = { StringEquals = { "AWS:SourceArn" = local.evidence_distribution.arn } }
    }]
  })
}

resource "aws_security_group" "registry_runner" {
  name        = "${var.project_name}-registry-runner"
  description = "Optional SSM runner: no inbound connections, outbound package retrieval."
  vpc_id      = aws_vpc.main.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "secrets_endpoint" {
  name   = "${var.project_name}-secrets-endpoint"
  vpc_id = aws_vpc.main.id
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id, aws_security_group.registry_runner.id]
  }
}

resource "aws_vpc_security_group_egress_rule" "lambda_postgres" {
  security_group_id            = aws_security_group.lambda.id
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_egress_rule" "lambda_secrets" {
  security_group_id            = aws_security_group.lambda.id
  referenced_security_group_id = aws_security_group.secrets_endpoint.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

resource "aws_vpc_endpoint" "secrets" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  private_dns_enabled = true
  security_group_ids  = [aws_security_group.secrets_endpoint.id]
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([{
      Effect    = "Allow"
      Principal = "*"
      Action    = ["secretsmanager:GetSecretValue"]
      Resource  = [aws_secretsmanager_secret.registry_reader.arn, aws_db_instance.main.master_user_secret[0].secret_arn]
      }], var.create_registry_runner ? [{
      Effect    = "Allow"
      Principal = "*"
      Action    = ["secretsmanager:PutSecretValue"]
      Resource  = [aws_secretsmanager_secret.registry_reader.arn]
      Condition = { ArnEquals = { "aws:PrincipalArn" = aws_iam_role.registry_runner[0].arn } }
    }] : [])
  })
}
# Handler does not read S3: stored evidence URLs need no S3 IAM or endpoint.
# Optional runner executes migrations/imports inside the VPC; RDS stays private.
resource "aws_iam_role" "registry_runner" {
  count = var.create_registry_runner ? 1 : 0
  name  = "${var.project_name}-registry-runner"
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}
resource "aws_iam_role_policy_attachment" "registry_runner_ssm" {
  count      = var.create_registry_runner ? 1 : 0
  role       = aws_iam_role.registry_runner[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy" "registry_runner" {
  count = var.create_registry_runner ? 1 : 0
  role  = aws_iam_role.registry_runner[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = "secretsmanager:GetSecretValue", Resource = aws_db_instance.main.master_user_secret[0].secret_arn },
      { Effect = "Allow", Action = "secretsmanager:PutSecretValue", Resource = aws_secretsmanager_secret.registry_reader.arn },
      { Effect = "Allow", Action = "s3:GetObject", Resource = "${aws_s3_bucket.data.arn}/imports/*" }
    ]
  })
}
resource "aws_iam_instance_profile" "registry_runner" {
  count = var.create_registry_runner ? 1 : 0
  role  = aws_iam_role.registry_runner[0].name
}
data "aws_ssm_parameter" "runner_ami" {
  count = var.create_registry_runner ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}
resource "aws_instance" "registry_runner" {
  count                       = var.create_registry_runner ? 1 : 0
  ami                         = data.aws_ssm_parameter.runner_ami[0].value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.registry_runner.id]
  iam_instance_profile        = aws_iam_instance_profile.registry_runner[0].name
  metadata_options { http_tokens = "required" }
  root_block_device { encrypted = true }
  tags = { Name = "${var.project_name}-registry-runner" }
}
