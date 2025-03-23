variable "region" {
  type        = string
  description = "The AWS region to deploy to"
  default     = "us-east-2"
}

variable "project" {
  type = string
  default = "devconnect-hunter"
}
