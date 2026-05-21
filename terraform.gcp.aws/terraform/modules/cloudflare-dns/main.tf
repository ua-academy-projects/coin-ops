terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

data "cloudflare_zone" "main" {
  filter = {
    name = var.cloudflare_zone_name
    account = trimspace(var.cloudflare_account_id) != "" ? {
      id = var.cloudflare_account_id
    } : null
  }
}

resource "cloudflare_dns_record" "aws" {
  count   = var.cloud == "aws" ? 1 : 0
  zone_id = data.cloudflare_zone.main.id
  name    = var.record_name
  type    = "CNAME"
  content = var.aws_lb_dns_name
  ttl     = 1
  proxied = var.proxied
}

resource "cloudflare_dns_record" "gcp" {
  count   = var.cloud == "gcp" ? 1 : 0
  zone_id = data.cloudflare_zone.main.id
  name    = var.record_name
  type    = "A"
  content = var.gcp_lb_ip_address
  ttl     = 1
  proxied = var.proxied
}

resource "cloudflare_dns_record" "azure" {
  count   = var.cloud == "azure" && var.enable_azure_record ? 1 : 0
  zone_id = data.cloudflare_zone.main.id
  name    = var.record_name
  type    = "A"
  content = var.azure_lb_ip_address
  ttl     = 1
  proxied = var.proxied
}
