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
}

# S3 bucket to hold the frontend distribution
resource "aws_s3_bucket" "frontend_bucket" {
  bucket = var.frontend_bucket
}


### CDN based on S3 bucket: CloudFront

resource "aws_cloudfront_distribution" "frontend_cloudfront" {
  origin {
    domain_name = aws_s3_bucket.frontend_bucket.bucket_regional_domain_name
    origin_id   = var.cloudfront_origin
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai_frontend.cloudfront_access_identity_path
    }
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  default_cache_behavior {
    allowed_methods = ["GET", "HEAD"]
    cached_methods = ["GET", "HEAD"]
    target_origin_id = var.cloudfront_origin
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
    cloudfront_default_certificate = true
  }
}

# Ensure access to the S3 bucket is always through CloudFront
resource "aws_cloudfront_origin_access_identity" "oai_frontend" {
  comment = "OAI for DevConnect-Hunter frontend"
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


### DNS

locals {
  contact_info = {
    first_name         = "Ray"
    last_name          = "Sinnema"
    address_line_1     = "9124 Harlequin Cir"
    city               = "Frederick"
    state              = "CO"
    country_code       = "US"
    zip_code           = "80504"
    phone_number       = "+1.7208381972"
    email              = "rssinnema@pm.me"
  }
}

resource "aws_route53domains_registered_domain" "domain" {
  domain_name = var.domain
  name_server {
    name = "ns-1.awsdns-1.com"
  }
  name_server {
    name = "ns-2.awsdns-2.org"
  }
  name_server {
    name = "ns-3.awsdns-3.net"
  }
  name_server {
    name = "ns-4.awsdns-4.co.uk"
  }
  admin_contact {
    first_name         = local.contact_info.first_name
    last_name          = local.contact_info.last_name
    address_line_1     = local.contact_info.address_line_1
    city               = local.contact_info.city
    state              = local.contact_info.state
    country_code       = local.contact_info.country_code
    zip_code           = local.contact_info.zip_code
    phone_number       = local.contact_info.phone_number
    email              = local.contact_info.email
  }
  registrant_contact {
    first_name         = local.contact_info.first_name
    last_name          = local.contact_info.last_name
    address_line_1     = local.contact_info.address_line_1
    city               = local.contact_info.city
    state              = local.contact_info.state
    country_code       = local.contact_info.country_code
    zip_code           = local.contact_info.zip_code
    phone_number       = local.contact_info.phone_number
    email              = local.contact_info.email
  }
  tech_contact {
    first_name         = local.contact_info.first_name
    last_name          = local.contact_info.last_name
    address_line_1     = local.contact_info.address_line_1
    city               = local.contact_info.city
    state              = local.contact_info.state
    country_code       = local.contact_info.country_code
    zip_code           = local.contact_info.zip_code
    phone_number       = local.contact_info.phone_number
    email              = local.contact_info.email
  }
  auto_renew = true
}

resource "aws_route53_zone" "dns_zone" {
  name = aws_route53domains_registered_domain.domain.domain_name
}

# Define the ACM certificate
resource "aws_acm_certificate" "my_certificate" {
  domain_name       = aws_route53_zone.dns_zone.name
  validation_method = "DNS"
  subject_alternative_names = ["www.${aws_route53_zone.dns_zone.name}"]
  lifecycle {
    create_before_destroy = true
  }
}

# Validate the ACM certificate using Route 53
resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.my_certificate.domain_validation_options : dvo.domain_name => {
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

resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.dns_zone.zone_id
  name    = "www.${aws_route53_zone.dns_zone.name}"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.frontend_cloudfront.domain_name
    zone_id                = aws_cloudfront_distribution.frontend_cloudfront.hosted_zone_id
    evaluate_target_health = false
  }
}
