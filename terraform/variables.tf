variable "region" {
  type        = string
  description = "The AWS region to deploy to"
  default     = "us-east-2"
}

variable "frontend_bucket" {
  type        = string
  description = "The S# bucket to deploy the frontend distribution into"
  default     = "devconnect-hunter-frontend"
}
