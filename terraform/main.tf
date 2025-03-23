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
  }
}

provider "aws" {
  region = var.region
  alias  = "main"
}

# ACM must be in us-east-1
provider "aws" {
  region = "us-east-1"
  alias  = "acm"
}

locals {
  origin = "${var.project}-cloudfront"
  domain = "${var.project}.org"
}


# S3 bucket to hold the frontend distribution
resource "aws_s3_bucket" "frontend_bucket" {
  bucket = "${var.project}-frontend"
}


### CDN based on S3 bucket: CloudFront

resource "aws_cloudfront_distribution" "frontend_cloudfront" {
  origin {
    domain_name = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_id   = local.origin
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai_frontend.cloudfront_access_identity_path
    }
  }
  aliases = [local.domain, "www.${local.domain}"]
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id = local.origin
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  price_class = "PriceClass_100"  # Cheapest: only North America & Europe
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cert.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# Ensure access to the S3 bucket is always through CloudFront
resource "aws_cloudfront_origin_access_identity" "oai_frontend" {
  comment = "OAI for ${var.project} frontend"
}

# Give CloudFront access to the S3 bucket
resource "aws_s3_bucket_policy" "frontend_bucket_access_policy" {
  bucket = aws_s3_bucket.frontend_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity ${aws_cloudfront_origin_access_identity.oai_frontend.iam_arn}"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.frontend_bucket.arn}/*"
      }
    ]
  })
}


### DNS: Route 53

# NOTE: DNS registration must be done manually via the AWS Console

resource "aws_route53_zone" "dns_zone" {
  name = local.domain
}

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.dns_zone.zone_id
  name    = "www"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.frontend_cloudfront.domain_name
    zone_id                = aws_cloudfront_distribution.frontend_cloudfront.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "apex" {
  zone_id = aws_route53_zone.dns_zone.zone_id
  name = ""  # Empty string for apex domain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.frontend_cloudfront.domain_name
    zone_id                = aws_cloudfront_distribution.frontend_cloudfront.hosted_zone_id
    evaluate_target_health = false
  }
}


### Certificate

resource "aws_acm_certificate" "cert" {
  provider          = aws.acm
  domain_name       = local.domain
  validation_method = "DNS"
  subject_alternative_names = [
    "www.${local.domain}"
  ]
  lifecycle {
    create_before_destroy = true
  }
}

# Create DNS records for certificate validation
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  allow_overwrite = true
  name            = each.value.name
  records = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.dns_zone.zone_id
}

# Validate the ACM certificate using Route 53
resource "aws_acm_certificate_validation" "cert_validation" {
  provider                = aws.acm
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
  timeouts {
    create = "6h"
  }
}


### Cognito

# User pool to store user identities
resource "aws_cognito_user_pool" "user_directory" {
  name = "${var.project}-user-pool"
  username_attributes = ["email"]
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }
  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject = "Your verification code"
    email_message = "Your verification code is {####}"
  }
  schema {
    name                = "email"
    attribute_data_type = "String"
    mutable             = true
    required            = true
  }
  schema {
    name                = "name"
    attribute_data_type = "String"
    mutable             = true
    required            = true
  }
  mfa_configuration = "OFF"
  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

# Client to access the user pool
resource "aws_cognito_user_pool_client" "user_pool_client" {
  name = "${var.project}-frontend"
  user_pool_id = aws_cognito_user_pool.user_directory.id
  generate_secret = false # No secret key for browser-based apps, since they can't store it securely
  refresh_token_validity = 30
  access_token_validity  = 1
  id_token_validity      = 1
  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
  allowed_oauth_flows  = ["implicit", "code"]
  allowed_oauth_scopes = ["email", "openid", "profile"]
  callback_urls = ["http://localhost:3000/callback", "https://${local.domain}/callback", "https://www.${local.domain}/callback"]
  logout_urls   = ["http://localhost:3000", "https://${local.domain}", "https://www.${local.domain}"]
  supported_identity_providers = ["COGNITO"]
  prevent_user_existence_errors = "ENABLED"
  enable_token_revocation = true
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]
}
