#####
##   Create a bucket
####
resource "aws_s3_bucket" "website" {
  bucket = local.bucket_name

  # versioning {
  #   enabled = local.environment_short == "prd" ? true : false
  # }

  tags = local.common_tags
}

resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  depends_on = [aws_s3_bucket.website]
}

resource "aws_s3_bucket_cors_configuration" "cors" {
  bucket = aws_s3_bucket.website.id

  cors_rule {
    allowed_methods = local.s3_allowed_methods
    allowed_origins = ["*"]
  }
}


resource "aws_s3_bucket_policy" "public_acl" {
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::${local.bucket_name}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.website_distribution.arn
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket.website, aws_s3_bucket_public_access_block.public_access]
}

#####
##   ACM
####

data "aws_acm_certificate" "cert" {
  # get existing ACM certificate
  domain      = var.acm-certificate-domain
  statuses    = ["ISSUED"]
  most_recent = true
}

#####
##   Cloudfront distribution
####

resource "aws_cloudfront_origin_access_control" "website" {
  name                              = local.bucket_name
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "website_distribution" {
  comment             = local.domain
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = concat([local.domain], local.extra_domains)

  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id                = "origin-bucket-${aws_s3_bucket.website.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
  }

  default_cache_behavior {
    allowed_methods  = local.allowed_methods
    cached_methods   = local.cache_methods
    target_origin_id = "origin-bucket-${aws_s3_bucket.website.id}"

    forwarded_values {
      query_string = true

      cookies {
        forward = "all"
      }
    }

    min_ttl     = local.ttl_times.min_ttl
    default_ttl = local.ttl_times.default_ttl
    max_ttl     = local.ttl_times.max_ttl
    compress    = true
    # viewer_protocol_policy = "allow-all"
    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    # cloudfront_default_certificate = true
    acm_certificate_arn = var.acm-certificate-arn != null ? var.acm-certificate-arn : data.aws_acm_certificate.cert.arn
    ssl_support_method  = "sni-only"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  tags = local.common_tags
}

#####
##   Add domain in route 53 cloudfront
####
data "aws_route53_zone" "main_zone" {
  count        = local.domain_dns != null ? 1 : 0
  name         = local.domain_dns
  private_zone = false
}

resource "aws_route53_record" "endpoint" {
  count   = local.domain_dns != null ? 1 : 0
  zone_id = data.aws_route53_zone.main_zone[0].zone_id
  name    = local.domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.website_distribution.hosted_zone_id
    evaluate_target_health = false
  }

}
