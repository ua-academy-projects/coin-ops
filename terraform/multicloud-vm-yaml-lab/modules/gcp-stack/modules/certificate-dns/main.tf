locals {
  domain_enabled = try(var.domain.enabled, false)
  create_dns     = local.domain_enabled && try(var.domain.create_records, true)
}

resource "google_compute_global_address" "app" {
  name = "${var.name_prefix}-lb-ip"
}

resource "google_compute_managed_ssl_certificate" "app" {
  count = local.domain_enabled ? 1 : 0

  name = "${var.name_prefix}-cert"

  managed {
    domains = [var.domain.name]
  }
}

resource "cloudflare_dns_record" "app" {
  count = local.create_dns ? 1 : 0

  zone_id = var.domain.cloudflare_zone_id
  name    = var.domain.name
  type    = "A"
  content = google_compute_global_address.app.address
  ttl     = 60
  proxied = false
}
