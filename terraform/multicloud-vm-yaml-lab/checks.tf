check "supported_cloud" {
  assert {
    condition     = contains(["aws", "gcp"], local.cloud)
    error_message = "config/lab.yaml cloud must be either aws or gcp."
  }
}

check "workspace_matches_cloud" {
  assert {
    condition     = terraform.workspace == "default" || terraform.workspace == local.cloud || terraform.workspace == "${local.cloud}-cloud-native"
    error_message = "Terraform workspace must match config/lab.yaml cloud. Use: terraform workspace select ${local.cloud}, or ${local.cloud}-cloud-native for runtime.mode=cloud-native."
  }
}

check "ssh_key_exists" {
  assert {
    condition     = fileexists(pathexpand(local.config.ssh.public_key_path))
    error_message = "ssh.public_key_path does not exist. Generate or fix the SSH public key path in config/lab.yaml."
  }
}

check "ssh_source_ranges_set" {
  assert {
    condition     = length(local.config.firewall.ssh_source_ranges) > 0
    error_message = "firewall.ssh_source_ranges must contain at least one CIDR; do not default SSH to the whole internet."
  }
}

check "cloudflare_zone_present_when_domain_enabled" {
  assert {
    condition     = !try(local.config.domain.enabled, false) || (try(local.config.domain.cloudflare_zone_id, "") != "" && try(local.config.domain.cloudflare_zone_id, "") != "REPLACE_WITH_CLOUDFLARE_ZONE_ID")
    error_message = "domain.enabled=true requires domain.cloudflare_zone_id to be set to the Cloudflare zone id."
  }
}


check "managed_db_password_set" {
  assert {
    condition     = local.runtime_mode != "cloud_native" || nonsensitive(var.db_password) != null
    error_message = "runtime.mode=cloud-native requires DB_PASSWORD exported as TF_VAR_db_password. scripts/lab.sh does this automatically after loading .env."
  }
}
