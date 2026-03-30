terraform {
  backend "s3" {
    bucket       = "demo-dev-008971668449-state-bucket-ap-southeast-2"
    key          = "infrastructure/demo-nowiz/terraform.tfstate"
    region       = "ap-southeast-2"
    encrypt      = true
    use_lockfile = true
  }
}
