# Route53 Hosted Zone (optional - for custom domain)
resource "aws_route53_zone" "gitlab_zone" {
  name = local.domain_name

  tags = local.common_tags
}

# Route53 Record for GitLab
resource "aws_route53_record" "gitlab_record" {
  zone_id = aws_route53_zone.gitlab_zone.zone_id
  name    = local.subdomain_name
  type    = local.record_type
  ttl     = local.ttl
  records = [aws_eip.gitlab_eip.public_ip]
}
