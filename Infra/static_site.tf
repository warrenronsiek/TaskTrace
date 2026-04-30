resource "aws_s3_bucket" "prefix_tasktrace_me" {
  bucket = local.tasktrace_static_site_url
}

resource "aws_s3_bucket_ownership_controls" "tasktrace_ownership_controls" {
  bucket = aws_s3_bucket.prefix_tasktrace_me.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "tasktrace_bucket_public_access_block" {
  bucket = aws_s3_bucket.prefix_tasktrace_me.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "tasktrace_www_bucket_acl" {
  depends_on = [
    aws_s3_bucket_ownership_controls.tasktrace_ownership_controls,
    aws_s3_bucket_public_access_block.tasktrace_bucket_public_access_block,
  ]

  bucket = aws_s3_bucket.prefix_tasktrace_me.id
  acl    = "private"
}

resource "aws_s3_object" "tasktrace_index_html" {
  bucket       = aws_s3_bucket.prefix_tasktrace_me.id
  key          = "index.html"
  source       = "index.html"
  etag         = filemd5("index.html")
  content_type = "text/html"
  lifecycle {
    ignore_changes = [etag]
  }
}

resource "aws_s3_bucket_policy" "tasktrace_bucket_policy" {
  bucket = aws_s3_bucket.prefix_tasktrace_me.id
  policy = data.aws_iam_policy_document.tasktrace_cloudfront_read.json
}

data "aws_iam_policy_document" "tasktrace_cloudfront_read" {
  statement {
    effect = "Allow"

    principals {
      type = "AWS"
      identifiers = [
        aws_cloudfront_origin_access_identity.tasktrace_me.iam_arn
      ]
    }

    actions = [
      "s3:GetObject"
    ]

    resources = [
      "${aws_s3_bucket.prefix_tasktrace_me.arn}/*"
    ]
  }
}


resource "aws_cloudfront_origin_access_identity" "tasktrace_me" {
  comment = local.tasktrace_static_site_url
}

resource "aws_wafv2_ip_set" "tasktrace_dev_allowlist" {
  count = terraform.workspace == "dev" ? 1 : 0

  provider           = aws.us_east_1
  name               = "tasktrace-dev-allowlist"
  scope              = "CLOUDFRONT"
  ip_address_version = "IPV4"
  addresses          = local.tasktrace_dev_waf_ipv4_allowlist
}

resource "aws_wafv2_web_acl" "tasktrace_dev_allowlist" {
  count = terraform.workspace == "dev" ? 1 : 0

  provider = aws.us_east_1
  name     = "tasktrace-dev-allowlist"
  scope    = "CLOUDFRONT"

  default_action {
    block {}
  }

  rule {
    name     = "allow-whitelisted-ips"
    priority = 0

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.tasktrace_dev_allowlist[0].arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "tasktraceDevAllowWhitelistedIps"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "tasktraceDevAllowlist"
    sampled_requests_enabled   = true
  }
}

resource "aws_cloudfront_distribution" "tasktrace_me" {
  enabled    = true
  web_acl_id = terraform.workspace == "dev" ? aws_wafv2_web_acl.tasktrace_dev_allowlist[0].arn : null

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = local.tasktrace_static_site_url
    viewer_protocol_policy = "redirect-to-https"
    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }
  }
  origin {
    domain_name = aws_s3_bucket.prefix_tasktrace_me.bucket_regional_domain_name
    origin_id   = local.tasktrace_static_site_url
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.tasktrace_me.cloudfront_access_identity_path
    }
  }

  price_class         = "PriceClass_100"
  default_root_object = "index.html"

  aliases = [
    local.tasktrace_static_site_url,
  ]
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn = local.tasktrace_cert_arn
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

  depends_on = [aws_s3_object.tasktrace_index_html]
}
