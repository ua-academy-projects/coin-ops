locals {
  active_record = var.cloud == "aws" ? cloudflare_dns_record.aws[0] : var.cloud == "gcp" ? cloudflare_dns_record.gcp[0] : length(cloudflare_dns_record.azure) > 0 ? cloudflare_dns_record.azure[0] : null
}

output "hostname" {
  value = local.active_record != null ? local.active_record.name : null
}

output "record_type" {
  value = local.active_record != null ? local.active_record.type : null
}

output "record_id" {
  value = local.active_record != null ? local.active_record.id : null
}
