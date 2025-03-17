terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "dev-connect-terraform-state"
    key    = "terraform.tfstate"
    region = var.region
  }
}

provider "aws" {
  region = var.region
}

resource "aws_s3_bucket" "frontend_bucket" {
  bucket = var.frontend_bucket
}
