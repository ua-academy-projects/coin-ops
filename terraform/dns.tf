# DNS Automation via Cloudflare
# This module dynamically updates the DNS records when instances are created or IP addresses change.

locals {
  # Extract the public IP of the UI node (app-1)
  # We use try() to handle cases where the module might be disabled or the instance doesn't have a public IP.
  ui_public_ip_gcp = local.gcp_enabled ? try(module.gcp_instances[0].instance_ips["app-1"].public_ip, "") : ""
  ui_public_ip_aws = local.aws_enabled ? try(module.aws_instances[0].instance_ips["app-1"].public_ip, "") : ""

  # Priority: GCP (primary) -> AWS (parity)
  target_ui_ip = local.ui_public_ip_gcp != "" ? local.ui_public_ip_gcp : local.ui_public_ip_aws

  # Only create records if the cloud is enabled and Cloudflare credentials are provided.
  # This must depend ONLY on variables known at plan-time to avoid "Invalid count" errors.
  dns_enabled = (local.gcp_enabled || local.aws_enabled) && local.effective_cloudflare_api_token != "" && var.cloudflare_zone_id != ""
}

# Root A record (e.g., coinops-d.pp.ua)
resource "cloudflare_record" "root_a" {
  count   = local.dns_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "@"
  value   = local.target_ui_ip
  type    = "A"
  proxied         = true
  ttl             = 1    # Low TTL for fast propagation during development
  allow_overwrite = true
}

# WWW CNAME record (e.g., www.coinops-d.pp.ua)
resource "cloudflare_record" "www_cname" {
  count   = local.dns_enabled ? 1 : 0
  zone_id = var.cloudflare_zone_id
  name    = "www"
  value   = var.app_domain
  type    = "CNAME"
  proxied         = true
  ttl             = 1
  allow_overwrite = true
}
