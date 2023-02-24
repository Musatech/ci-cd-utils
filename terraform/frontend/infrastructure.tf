#####
##   Create a bucket
####
resource "aws_s3_bucket" "website" {
  bucket = local.bucket_name
  acl    = "public-read"

  website {
    index_document = "index.html"
    error_document = "index.html"
  }

  cors_rule {
    allowed_methods = local.s3_allowed_methods
    allowed_origins = ["*"]
  }

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "PublicReadGetObject",
        "Effect" : "Allow",
        "Principal" : "*",
        "Action" : "s3:*",
        "Resource" : "arn:aws:s3:::${local.bucket_name}/*"
      }
    ]
  })
  # versioning {
  #   enabled = local.environment_short == "prd" ? true : false
  # }

  tags = local.common_tags

}

#####
##   ACM
####

data "aws_acm_certificate" "cert" {
  # get existing ACM certificate
  domain   = local.acm_domain
  statuses = ["ISSUED"]
}

#####
##   Cloudfront distribution
####

resource "aws_cloudfront_distribution" "website_distribution" {
  comment             = local.domain
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  aliases = [local.domain]

  origin {
    domain_name = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id   = "origin-bucket-${aws_s3_bucket.website.id}"
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
    acm_certificate_arn = data.aws_acm_certificate.cert.arn
    ssl_support_method  = "sni-only"
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/"
  }

  tags = local.common_tags
}

#####
##   Add domain in route 53 cloudfront
####
data "aws_route53_zone" "main_zone" {
  name         = local.domain_dns
  private_zone = false
}

resource "aws_route53_record" "endpoint" {
  zone_id = data.aws_route53_zone.main_zone.zone_id
  name    = local.domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.website_distribution.hosted_zone_id
    evaluate_target_health = false
  }

}
