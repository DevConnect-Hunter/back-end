variable "region" {
  type        = string
  description = "The AWS region to deploy to"
  default     = "us-east-2"
}

variable "frontend_bucket" {
  type        = string
  description = "The S3 bucket to deploy the frontend distribution into"
  default     = "devconnect-hunter-frontend"
}

variable "cloudfront_origin" {
  type = string
  description = "The origin ID of the CloudFront distribution"
  default = "devconnect-hunter-cloudfront"
}