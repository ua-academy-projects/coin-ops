locals {
  root_active_infra = local.config.cloud == "aws" ? module.aws_infra[0] : module.gcp_infra[0]
}

output "bastion_external_ip" {
  value = local.root_active_infra.bastion_external_ip
}

output "bastion_internal_ip" {
  value = local.root_active_infra.bastion_internal_ip
}

output "private_internal_ips" {
  value = local.root_active_infra.private_internal_ips
}

output "load_balancer_dns_name" {
  value = local.root_active_infra.load_balancer_dns_name
}

output "load_balancer_ip_address" {
  value = local.root_active_infra.load_balancer_ip_address
}

output "cloudflare_record_hostname" {
  value = var.cloudflare_zone_name != "" ? module.cloudflare_dns[0].hostname : null
}

output "cloudflare_record_type" {
  value = var.cloudflare_zone_name != "" ? module.cloudflare_dns[0].record_type : null
}
