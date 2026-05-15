# DNS Automation via Cloudflare.
# The root app domain belongs to one primary cloud; parallel cloud deployments
# receive cloud-specific aliases such as gcp.example.com and aws.example.com.

locals {
  dns_primary_cloud = try(local.dns.primary_cloud, local.control_plane_cloud)
  dns_cloud_subdomains = try(local.dns.cloud_subdomains, {
    gcp = "gcp"
    aws = "aws"
  })
  dns_ttl     = try(local.cloudflare_config.ttl, 60)
  dns_proxied = try(local.cloudflare_config.proxied, false)

  gcp_has_ui = local.gcp_enabled && contains(keys(local.gcp_instances_base), "app-1")
  aws_has_ui = local.aws_enabled && contains(keys(local.aws_instances_base), "app-1")

  ui_public_ips = {
    gcp = local.gcp_has_ui ? try(module.gcp_instances[0].instance_ips["app-1"].public_ip, "") : ""
    aws = local.aws_has_ui ? try(module.aws_instances[0].instance_ips["app-1"].public_ip, "") : ""
  }

  cloud_has_ui = {
    gcp = local.gcp_has_ui
    aws = local.aws_has_ui
  }

  dns_has_api_token  = nonsensitive(local.effective_cloudflare_api_token) != ""
  dns_enabled        = (local.gcp_enabled || local.aws_enabled) && local.dns_has_api_token && local.cloudflare_zone_id != ""
  dns_primary_has_ui = lookup(local.cloud_has_ui, local.dns_primary_cloud, false)
  dns_alias_records = {
    for cloud, label in local.dns_cloud_subdomains : cloud => label
    if local.dns_enabled && cloud != local.dns_primary_cloud && lookup(local.cloud_has_ui, cloud, false)
  }
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

resource "cloudflare_record" "cloud_alias_a" {
  for_each = local.dns_alias_records

  zone_id         = local.cloudflare_zone_id
  name            = each.value
  content         = local.ui_public_ips[each.key]
  type            = "A"
  proxied         = local.dns_proxied
  ttl             = local.dns_ttl
  allow_overwrite = true
}
