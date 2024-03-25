terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.36.0"
    }
  }
}

# ~~~~~~~~~~~~~~~~~~~~ Configure the AWS provider ~~~~~~~~~~~~~~~~~~~~

provider "aws" {
  region = var.region
}
 
# ~~~~~~~~~~~~~~~~~~~~~~~~ Create the bucket ~~~~~~~~~~~~~~~~~~~~~~~~~~

resource "aws_s3_bucket" "bucket1" {

  bucket = var.bucket_name
  force_destroy = true
  
}

resource "aws_s3_bucket_acl" "example" {
  bucket = aws_s3_bucket.bucket1.id
  acl    = "private"
}

# ~~~~~~~~~~~~~~~~~ Upload the site content in the bucket ~~~~~~~~~~~~~

resource "null_resource" "upload_files" {

  provisioner "local-exec"  {
      command = <<EOT
        aws s3 sync ${var.cp-path} s3://${aws_s3_bucket.bucket1.bucket}/ 
      EOT
}
 
depends_on = [aws_s3_bucket.bucket1]
 
}


# ~~~~~~~~~~~ Configure the web hosting parameters in the bucket ~~~~~~~

resource "aws_s3_bucket_website_configuration" "bucket" {
  bucket = aws_s3_bucket.bucket1.id

  index_document {
    suffix = var.file-key
  }

  error_document {
    key = var.file-key
  }
}

resource "aws_s3_bucket_public_access_block" "bucket_access_block" {
  bucket = aws_s3_bucket.bucket1.id

  block_public_acls   = false
  block_public_policy = false
}

# ~~~~~~~~~~~~~~~~~~~~~~ Create the bucket policy ~~~~~~~~~~~~~~~~~~~~~

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.bucket1.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.bucket1.arn}/*"
        ]
      }
    ]
  })
}

# ~~~~~~~~~~~~~~~~~~~~~~ Configure CloudFont ~~~~~~~~~~~~~~~~~~~~~

locals {
  s3_origin_id   = "${var.bucket_name}-origin"
  s3_domain_name = "${var.bucket_name}.s3-website.${var.region}.amazonaws.com"
}

resource "aws_cloudfront_distribution" "web-distribution" {
  
  enabled = true
  
  origin {
    origin_id                = local.s3_origin_id
    domain_name              = local.s3_domain_name
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1"]
    }
  }

  default_cache_behavior {
    
    target_origin_id = local.s3_origin_id
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]

    forwarded_values {
      query_string = true

      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    cloudfront_default_certificate = true
  }

  price_class = "PriceClass_200"

  depends_on = [ aws_s3_bucket.bucket1 , null_resource.upload_files , aws_s3_bucket_website_configuration.bucket , aws_s3_bucket_public_access_block.bucket_access_block , aws_s3_bucket_policy.bucket_policy]
  
}

output "INFO" {
  value = "AWS Resources  has been provisioned. Go to http://${aws_cloudfront_distribution.web-distribution.domain_name}"
}
