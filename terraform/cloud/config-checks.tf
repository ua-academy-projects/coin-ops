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
