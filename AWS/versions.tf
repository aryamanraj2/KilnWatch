terraform {
  required_version = ">= 1.10"

  # Partial config: values come from the ignored backend.hcl (see backend.hcl.example).
  backend "s3" {}

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.38"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# Account that hosts the evidence CDN (see evidence_cdn_account). Same provider, no new lock entry.
provider "aws" {
  alias   = "cdn"
  region  = var.aws_region
  profile = var.cdn_profile != "" ? var.cdn_profile : null

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
