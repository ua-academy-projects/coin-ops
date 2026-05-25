locals {
  split_dns_enabled = try(local.config.domain.enabled, false) && try(local.config.domain.create_records, true) && local.is_azure
  cloudflare_ttl    = try(local.config.domain.cloudflare_proxy, false) ? 1 : 60

  # k3s ingress wildcard (GCP path). Points *.<k3s_ingress_domain> at the k3s
  # node private IPs (round-robin) — reachable only via the tailnet, so the
  # records are DNS-only (never proxied through Cloudflare).
  k3s_ingress_domain = try(local.config.domain.k3s_ingress, "lab.coinops.pp.ua")
  k3s_dns_enabled = local.is_gcp && length(local.k3s_names) > 0 && try(local.config.domain.create_records, false) && try(local.config.domain.cloudflare_zone_id, "") != "" && try(local.config.domain.cloudflare_zone_id, "") != "REPLACE_WITH_CLOUDFLARE_ZONE_ID"
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

# Wildcard for the GCP k3s ingress: *.<k3s_ingress_domain> -> k3s node private
# IPs. One A record per node (round-robin); DNS-only because the targets are
# private IPs reachable only over the tailnet via the bastion subnet-router.
resource "cloudflare_dns_record" "k3s_ingress_wildcard" {
  for_each = local.k3s_dns_enabled ? toset(local.k3s_names) : toset([])

  zone_id = local.config.domain.cloudflare_zone_id
  name    = "*.${local.k3s_ingress_domain}"
  type    = "A"
  content = local.instances[each.key].private_ip
  ttl     = 60
  proxied = false
}
