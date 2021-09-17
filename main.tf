locals {
  region      = var.region
  env         = var.env
  domain      = var.dns.domain
  dns-zone-id = var.dns.zone-id
  domain-cert = var.dns.certificate-arn
  origin-id   = "website-maintenance"
}

resource "aws_s3_bucket" "maintenance" {
  bucket        = "maintenance-${local.env}"
  acl           = "private"
  force_destroy = true
  website {
    index_document = "maintenance.html"
    error_document = "maintenance.html"
  }
  server_side_encryption_configuration {
    rule {

      /* If you are using custom KMS key, add your KMS Key Id to this section */
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
      }
    }
  }

  // If you have S3 access logging turned on, uncomment this section.
  /*
  logging {
    target_bucket = "put-logs-bucket-id-here"
    target_prefix = "maintenance/"
  }
  */

  tags = {
    Name : "maintenance-${local.env}"
  }
}

resource "aws_s3_bucket_object" "errorcss" {
  bucket       = aws_s3_bucket.maintenance.bucket
  content_type = "text/css"
  key          = "error.css"
  source       = "./maintenance/pages/error.css"
}

resource "aws_s3_bucket_object" "errorhtml" {
  bucket        = aws_s3_bucket.maintenance.bucket
  content_type  = "text/html"
  key           = "error.html"
  source        = "./maintenance/pages/error.html"
  cache_control = "public, max-age=0, must-revalidate"
}

resource "aws_s3_bucket_object" "maintenancecss" {
  bucket       = aws_s3_bucket.maintenance.bucket
  content_type = "text/css"
  key          = "maintenance.css"
  source       = "./maintenance/pages/maintenance.css"
}

resource "aws_s3_bucket_object" "maintenancehtml" {
  bucket        = aws_s3_bucket.maintenance.bucket
  content_type  = "text/html"
  key           = "maintenance.html"
  source        = "./maintenance/pages/maintenance.html"
  cache_control = "public, max-age=0, must-revalidate"
}

resource "aws_cloudfront_distribution" "maintenance-cdn" {
  origin {
    domain_name = aws_s3_bucket.maintenance.website_endpoint
    origin_id   = local.origin-id
    custom_origin_config {
      origin_protocol_policy = "http-only"
      http_port              = 80
      https_port             = 443
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "maintenance.html"
  aliases             = [local.domain]
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = local.origin-id
    compress         = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    lambda_function_association {
      event_type   = "origin-request"
      lambda_arn   = module.lambda-cf-edge-s3.out.qualified-arn
      include_body = false
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 1
    default_ttl            = 86400
    max_ttl                = 31536000
  }

  price_class = "PriceClass_All"
  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn            = local.domain-cert
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2021"
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Name : "maintenance-${local.env}"
  }
}

resource "aws_s3_bucket_public_access_block" "maintenance" {
  bucket = aws_s3_bucket.maintenance.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_route53_record" "failover-secondary" {
  name = local.domain
  type = "A"
  alias {
    name                   = aws_cloudfront_distribution.maintenance-cdn.domain_name
    zone_id                = "Z2FDTNDATAQYW2"
    evaluate_target_health = false
  }
  failover_routing_policy {
    type = "SECONDARY"
  }
  set_identifier = "${local.domain}-secondary"
  zone_id        = local.dns-zone-id
}
