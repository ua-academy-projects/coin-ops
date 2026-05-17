# DNS Automation via Cloudflare.
# The root app domain belongs to one primary cloud only.
# Non-primary cloud deployments are intentionally tested by direct public IP.

locals {
  dns_primary_cloud = try(local.dns.primary_cloud, local.control_plane_cloud)
  dns_ttl           = try(local.cloudflare_config.ttl, 60)
  dns_proxied       = try(local.cloudflare_config.proxied, false)

  gcp_has_ui   = local.gcp_compute_enabled && contains(keys(local.gcp_instances_base), "app-1")
  aws_has_ui   = local.aws_compute_enabled && contains(keys(local.aws_instances_base), "app-1")
  azure_has_ui = local.azure_compute_enabled && contains(keys(local.azure_instances_base), "app-1")

  ui_public_ips = {
    gcp   = local.gcp_has_ui ? try(module.gcp_instances[0].instance_ips["app-1"].public_ip, "") : ""
    aws   = local.aws_has_ui ? try(module.aws_instances[0].instance_ips["app-1"].public_ip, "") : ""
    azure = local.azure_has_ui ? try(module.azure_instances[0].instance_ips["app-1"].public_ip, "") : ""
  }

  cloud_has_ui = {
    gcp   = local.gcp_has_ui
    aws   = local.aws_has_ui
    azure = local.azure_has_ui
  }

  dns_has_api_token  = nonsensitive(local.effective_cloudflare_api_token) != ""
  dns_enabled        = (local.gcp_enabled || local.aws_enabled || local.azure_enabled) && local.dns_has_api_token && local.cloudflare_zone_id != ""
  dns_primary_has_ui = lookup(local.cloud_has_ui, local.dns_primary_cloud, false)
}

# Root A record (e.g., coinops-d.pp.ua)
resource "cloudflare_record" "root_a" {
  count           = local.dns_enabled && local.dns_primary_has_ui ? 1 : 0
  zone_id         = local.cloudflare_zone_id
  name            = "@"
  content         = local.ui_public_ips[local.dns_primary_cloud]
  type            = "A"
  proxied         = local.dns_proxied
  ttl             = local.dns_ttl
  allow_overwrite = true
}

# WWW CNAME record (e.g., www.coinops-d.pp.ua)
resource "cloudflare_record" "www_cname" {
  count           = local.dns_enabled && local.dns_primary_has_ui ? 1 : 0
  zone_id         = local.cloudflare_zone_id
  name            = "www"
  content         = local.app_domain
  type            = "CNAME"
  proxied         = local.dns_proxied
  ttl             = local.dns_ttl
  allow_overwrite = true
}
