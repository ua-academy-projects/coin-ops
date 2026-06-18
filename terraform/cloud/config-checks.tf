# config-checks.tf
# -> validates shared json config before module inputs are built

check "config_cloud" {
  assert {
    condition     = contains(["gcp", "aws", "azure"], local.default_cloud)
    error_message = "config cloud must be one of: gcp, aws, azure."
  }
}

check "config_network_clouds" {
  assert {
    condition = alltrue([
      for _, network in local.config.networks :
      try(network.cloud, null) == null || contains(["gcp", "aws", "azure"], network.cloud)
    ])
    error_message = "Each network cloud must be omitted or one of: gcp, aws, azure."
  }
}

check "config_workload_clouds" {
  assert {
    condition = alltrue([
      for _, workload in try(local.config.workloads, {}) :
      try(workload.cloud, null) == null || contains(["gcp", "aws", "azure"], workload.cloud)
    ])
    error_message = "Each workload cloud must be omitted or one of: gcp, aws, azure."
  }
}

check "azure_provider_inputs" {
  assert {
    condition = local.default_cloud != "azure" || alltrue([
      try(length(trimspace(local.config_azure_resource_group)) > 0, false),
      try(length(trimspace(local.config_azure_key_vault_name)) > 0, false),
      try(length(trimspace(local.config_azure_location)) > 0, false)
    ])
    error_message = "Azure configs require azure_resource_group_name, azure_key_vault_name, and azure_location. Run bootstrap/azure-bootstrap.sh to generate terraform/cloud/azure.auto.tfvars.json, or define provider.azure in the selected config JSON."
  }
}
