terraform {
  backend "s3" {
    bucket       = "demo-dev-058432329173-state-bucket-ap-southeast-2"
    key          = "bootstrap/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
