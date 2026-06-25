# ---------------------------------------------------------------------
# viewer DNS: pr-<n>.preview.<domain> → CloudFront
# ---------------------------------------------------------------------
resource "aws_route53_record" "viewer_a" {
  zone_id = local.s.route53_zone_id
  name    = local.subdomain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "viewer_aaaa" {
  zone_id = local.s.route53_zone_id
  name    = local.subdomain
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
