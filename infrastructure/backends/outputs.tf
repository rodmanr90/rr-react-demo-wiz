output "backend_config" {
  description = "Backend configuration for use in other Terraform configurations"
  value = {
    state = {
      bucket = aws_s3_bucket.state.id
      region = var.aws_region
    }
  }
}
