locals {
  split_dns_enabled = try(local.config.domain.enabled, false) && try(local.config.domain.create_records, true) && local.is_azure
  cloudflare_ttl    = try(local.config.domain.cloudflare_proxy, false) ? 1 : 60
}

resource "cloudflare_dns_record" "ui" {
  count = local.split_dns_enabled ? 1 : 0

  zone_id = local.config.domain.cloudflare_zone_id
  name    = local.stack.ui.domain
  type    = local.ui_endpoint_type
  content = local.ui_endpoint
  ttl     = local.cloudflare_ttl
  proxied = try(local.config.domain.cloudflare_proxy, false)
}

resource "cloudflare_dns_record" "api" {
  count = local.split_dns_enabled ? 1 : 0

  zone_id = local.config.domain.cloudflare_zone_id
  name    = local.stack.api.domain
  type    = local.backend_endpoint_type
  content = local.backend_endpoint
  ttl     = local.cloudflare_ttl
  proxied = try(local.config.domain.cloudflare_proxy, false)
}
