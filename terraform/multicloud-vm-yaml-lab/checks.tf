check "supported_cloud" {
  assert {
    condition     = contains(["aws", "gcp", "azure"], local.cloud)
    error_message = "config/lab.yaml cloud must be aws, gcp, or azure."
  }
}

check "workspace_matches_cloud" {
  assert {
    condition     = terraform.workspace == "default" || terraform.workspace == local.backend_cloud || terraform.workspace == "${local.backend_cloud}-cloud-native"
    error_message = "Terraform workspace must match the backend cloud. Use: terraform workspace select ${local.backend_cloud}, or ${local.backend_cloud}-cloud-native for runtime.mode=cloud-native."
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
    error_message = "runtime.mode=cloud-native requires DB_PASSWORD exported as TF_VAR_db_password while managed PostgreSQL is provisioned."
  }
}

check "api_domain_matches_backend_cloud" {
  assert {
    condition     = !try(local.config.domain.enabled, false) || local.backend_cloud == local.cloud
    error_message = "domain.api.cloud must match the root cloud/backend cloud in config/lab.yaml."
  }
}

check "ui_cloud_supported" {
  assert {
    condition     = contains(["aws", "gcp", "azure"], local.ui_cloud)
    error_message = "domain.ui.cloud must be aws, gcp, or azure."
  }
}
