terraform {
  backend "s3" {
    bucket = "dev-connect-terraform-state"
    key    = "terraform.tfstate"
    region = "us-east-2"
  }
}

resource "aws_s3_bucket" "frontend_bucket" {
  bucket = "dev-connect-frontend"
}
