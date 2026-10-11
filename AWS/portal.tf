# Resident portal hosting (prompt 37). Same pattern as the second-account evidence CDN in
# bridge.tf: a private bucket in the main account, served only through a CloudFront
# distribution with an OAC in the second account (aws.cdn).

resource "aws_s3_bucket" "portal" {
  count         = var.enable_portal_hosting ? 1 : 0
  bucket_prefix = "${var.project_name}-portal-"
}

resource "aws_s3_bucket_public_access_block" "portal" {
  count                   = var.enable_portal_hosting ? 1 : 0
  bucket                  = aws_s3_bucket.portal[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "portal" {
  count  = var.enable_portal_hosting ? 1 : 0
  bucket = aws_s3_bucket.portal[0].id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "portal" {
  count  = var.enable_portal_hosting ? 1 : 0
  bucket = aws_s3_bucket.portal[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "portal" {
  count  = var.enable_portal_hosting ? 1 : 0
  bucket = aws_s3_bucket.portal[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "CloudFrontPortalOnly"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.portal[0].arn}/*"
      Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.portal[0].arn } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.portal]
}

resource "aws_cloudfront_origin_access_control" "portal" {
  provider                          = aws.cdn
  count                             = var.enable_portal_hosting ? 1 : 0
  name                              = "${var.project_name}-portal"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# SPA routes (/kilns/<id>, /ask, ...) have no file extension and get index.html.
# Anything with an extension goes to S3 as-is, so a missing asset stays a 403, never HTML.
resource "aws_cloudfront_function" "portal_rewrite" {
  provider = aws.cdn
  count    = var.enable_portal_hosting ? 1 : 0
  name     = "${var.project_name}-portal-spa-rewrite"
  runtime  = "cloudfront-js-2.0"
  comment  = "Rewrite extensionless paths to /index.html"
  publish  = true
  code     = <<-EOT
    function handler(event) {
      var request = event.request;
      var last = request.uri.substring(request.uri.lastIndexOf('/') + 1);
      if (last.indexOf('.') === -1) {
        request.uri = '/index.html';
      }
      return request;
    }
  EOT
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  provider = aws.cdn
  count    = var.enable_portal_hosting ? 1 : 0
  name     = "Managed-CachingOptimized"
}

data "aws_cloudfront_response_headers_policy" "security_headers" {
  provider = aws.cdn
  count    = var.enable_portal_hosting ? 1 : 0
  name     = "Managed-SecurityHeadersPolicy"
}

resource "aws_cloudfront_distribution" "portal" {
  provider            = aws.cdn
  count               = var.enable_portal_hosting ? 1 : 0
  enabled             = true
  comment             = "Resident portal static build; origin bucket stays private in the main account."
  default_root_object = "index.html"
  price_class         = "PriceClass_200"
  origin {
    domain_name              = aws_s3_bucket.portal[0].bucket_regional_domain_name
    origin_id                = "portal"
    origin_access_control_id = aws_cloudfront_origin_access_control.portal[0].id
  }
  default_cache_behavior {
    target_origin_id           = "portal"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized[0].id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers[0].id
    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.portal_rewrite[0].arn
    }
  }
  restrictions {
    geo_restriction { restriction_type = "none" }
  }
  viewer_certificate { cloudfront_default_certificate = true }
}
