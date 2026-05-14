locals {
  active_record = var.cloud == "aws" ? cloudflare_dns_record.aws[0] : cloudflare_dns_record.gcp[0]
}

output "hostname" {
  value = local.active_record.name
}

output "record_type" {
  value = local.active_record.type
}

output "record_id" {
  value = local.active_record.id
}
