# Back end

## Overview

This repository contains [Terraform](https://developer.hashicorp.com/terraform/intro) code to deploy a static React
frontend to AWS using the following services:

- [Amazon S3](https://docs.aws.amazon.com/s3/): Hosts the frontend assets, as well as the Terraform state
- [Amazon CloudFront](https://docs.aws.amazon.com/cloudfront/): Provides a CDN for efficient content delivery
- [AWS Route 53](https://docs.aws.amazon.com/route53/): Manages the domain and its DNS records
- [AWS Certificate Manager](https://docs.aws.amazon.com/acm/): Provides an SSL certificate for secure HTTPS access

## Architecture Diagram

```plaintext
          Users
            │
            ▼
    +----------------+
    | Route 53 (DNS) |
    +----------------+
            │
            ▼
    +--------------------+
    | CloudFront (CDN)   |
    +--------------------+
            │
            ▼
    +----------------+
    | S3 (Frontend)  |
    +----------------+
```

## AWS Resources

### 1. Amazon S3 (Frontend Bucket)

A dedicated S3 bucket is used to store and serve static frontend assets.
Access is restricted via CloudFront Origin Access Identity (OAI), so that only CloudFront has access.

### 2. Amazon CloudFront (CDN)

CloudFront is configured to cache and serve the frontend efficiently.
The certificate is managed by AWS ACM.

### 3. AWS Route 53 (DNS)

A Route 53 hosted zone is created for the domain, with records pointing to CloudFront.
Terraform does not register the domain; this was done manually in AWS Route 53 (because it costs money).

### 4. AWS ACM (SSL Certificate)

A wildcard SSL certificate is created for secure HTTPS access.
It's auto-validated via Route 53 DNS records.

## Deployment Steps

A backend GitHub [workflow](.github/workflows/deploy-infra.yml) deploys the infrastructure via
[Terraform](https://developer.hashicorp.com/terraform/intro).

A frontend GitHub [workflow](https://github.com/DevConnect-Hunter/front-end/blob/main/.github/workflows/deploy-frontend.yml)
builds the React app, uploads it to S3, and invalidates the CloudFront distribution.
