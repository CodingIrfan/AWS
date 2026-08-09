terraform {
  backend "s3" {
    bucket = "s3-backend-state-dev-bucket"
    key    = "eks/terraform.tfstate"
    region = "us-east-1"
    use_lockfile = true
  }
}