locals {
  # Split-DNS ui/api records apply only to the Azure cloud-native VM mode (there
  # is an app gateway / LB to point at). In k3s-only mode there is no LB and the
  # Cloudflare zero-trust tunnels publish the per-app proxied CNAMEs instead, so
  # skip these (they would otherwise point at an empty backend_endpoint).
  split_dns_enabled = try(local.config.domain.enabled, false) && try(local.config.domain.create_records, true) && local.is_azure && !try(local.stack.azure.k3s_only, false)
  cloudflare_ttl    = try(local.config.domain.cloudflare_proxy, false) ? 1 : 60

  # Base domain for the GCP k3s ingress hosts (<app>.<this>). The Cloudflare
  # zero-trust module (cloudflare_zerotrust.tf) builds the per-app proxied
  # CNAMEs from this. Kept single-level (directly under the zone apex) so
  # Cloudflare's edge certificate covers every <app>.<domain> host — a
  # second-level domain like app.lab.<zone> is NOT covered by free Universal SSL.
  k3s_ingress_domain = try(local.config.domain.k3s_ingress, "coinops.pp.ua")
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

# The old *.<k3s_ingress_domain> wildcard A-record (tailnet path) was removed:
# the Cloudflare zero-trust tunnels now publish per-app proxied CNAMEs
# (cloudflare_zerotrust.tf), and a wildcard at the single-level domain would
# shadow the entire zone. Applying this change deletes the legacy wildcard.
