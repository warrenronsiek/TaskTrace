resource "aws_route53_record" "tasktrace_route_static_site" {
  name    = local.tasktrace_static_site_url
  type    = "A"
  zone_id = local.tasktrace_route53_zone_id

  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.tasktrace_me.domain_name
    zone_id                = aws_cloudfront_distribution.tasktrace_me.hosted_zone_id
  }

  depends_on = [
    aws_cloudfront_distribution.tasktrace_me
  ]
}

resource "aws_route53_record" "tasktrace_www_redirect" {
  name    = local.www_tasktrace_url
  type    = "A"
  zone_id = local.tasktrace_route53_zone_id
  count   = terraform.workspace == "prod" ? 1 : 0
  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.tasktrace_me.domain_name
    zone_id                = aws_cloudfront_distribution.tasktrace_me.hosted_zone_id
  }

  depends_on = [
    aws_cloudfront_distribution.tasktrace_me
  ]
}