locals {
  domain_enabled = try(var.domain.enabled, false)
  create_dns     = local.domain_enabled && try(var.domain.create_records, true)
}

resource "aws_acm_certificate" "app" {
  count = local.domain_enabled ? 1 : 0

  domain_name       = var.domain.name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${var.name_prefix}-cert" }
}

locals {
  certificate_validation_records = local.domain_enabled ? {
    (var.domain.name) = {
      name    = one(aws_acm_certificate.app[0].domain_validation_options).resource_record_name
      type    = one(aws_acm_certificate.app[0].domain_validation_options).resource_record_type
      content = one(aws_acm_certificate.app[0].domain_validation_options).resource_record_value
    }
  } : {}
}

resource "cloudflare_dns_record" "cert_validation" {
  for_each = local.create_dns ? local.certificate_validation_records : {}

  zone_id = var.domain.cloudflare_zone_id
  name    = each.value.name
  type    = each.value.type
  content = each.value.content
  ttl     = 60
  proxied = false
}

resource "aws_acm_certificate_validation" "app" {
  count = local.domain_enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.app[0].arn
  validation_record_fqdns = local.create_dns ? [for record in cloudflare_dns_record.cert_validation : record.name] : []
}

resource "aws_lb_listener" "https" {
  count = local.domain_enabled ? 1 : 0

  load_balancer_arn = var.lb_arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.app[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = var.target_group_arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  count = local.domain_enabled ? 1 : 0

  load_balancer_arn = var.lb_arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "http_fallback" {
  count = local.domain_enabled ? 0 : 1

  load_balancer_arn = var.lb_arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = var.target_group_arn
  }
}

resource "cloudflare_dns_record" "app" {
  count = local.create_dns ? 1 : 0

  zone_id = var.domain.cloudflare_zone_id
  name    = var.domain.name
  type    = "CNAME"
  content = var.lb_dns_name
  ttl     = 60
  proxied = false
}
