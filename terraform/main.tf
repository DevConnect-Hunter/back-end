terraform {
  backend "s3" {
    bucket = "dev-connect-terraform-state  Info"
    key    = "terraform.tfstate"
    region = "us-east-2"
  }
}
