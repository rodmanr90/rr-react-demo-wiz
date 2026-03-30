# Bootstrap infrastructure for Terraform state management

data "aws_caller_identity" "current" {}

locals {
  # Deterministic bucket name so committed iac_config.wiz stays valid even if the
  # backend is destroyed/recreated in CI (same AWS account + region).
  bucket_name = "demo-${var.environment}-${data.aws_caller_identity.current.account_id}-state-bucket-${var.aws_region}"
}

resource "aws_s3_bucket" "state" {
  bucket        = local.bucket_name
  force_destroy = true

  tags = {
    Name        = local.bucket_name
    Environment = var.environment
    Purpose     = "Terraform State"
    Branch      = var.branch
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
