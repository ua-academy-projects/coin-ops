locals {
  workload_identity_principal_ids = {
    for workload_name, workload in var.workloads :
    try(workload.identity, workload.service_account, workload_name) => var.managed_identity_principal_ids[workload_name]
    if try(workload.identity, workload.service_account, null) != null &&
    try(var.managed_identity_principal_ids[workload_name], null) != null
  }

  access_bindings = {
    for key, cfg in var.secret_access : key => {
      identity_key = try(cfg.identity, cfg.service_account, "")
      principal_id = lookup(local.workload_identity_principal_ids, try(cfg.identity, cfg.service_account, ""), null)
    }
    if try(cfg.identity, cfg.service_account, "") != "" &&
    lookup(local.workload_identity_principal_ids, try(cfg.identity, cfg.service_account, ""), null) != null
  }
}
