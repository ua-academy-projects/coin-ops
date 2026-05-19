locals {
  azure = {
    resource_group_name = var.azure_resource_group_name
    key_vault_name      = var.azure_key_vault_name
    location            = var.azure_location
  }

  normalized_secrets             = var.secrets
  normalized_workload_identities = {}

  private_ips = var.cloud == "gcp" ? try(module.gcp_instances[0].private_ips, {}) : (
    var.cloud == "azure" ? try(module.azure_instances[0].private_ips, {}) : try(module.aws_instances[0].private_ips, {})
  )
  public_ips = var.cloud == "gcp" ? try(module.gcp_instances[0].public_ips, {}) : (
    var.cloud == "azure" ? try(module.azure_instances[0].public_ips, {}) : try(module.aws_instances[0].public_ips, {})
  )

  inventory_role_tags = {
    history = "history-api"
    proxy   = "proxy-api"
    ui      = "ui"
    bastion = "bastion"
    nat     = "nat"
  }

  inventory_hosts = {
    for role, tag in local.inventory_role_tags :
    role => one([
      for name, workload in var.workloads : name
      if contains(workload.tags, tag)
    ])
  }

  inventory_host_records = {
    for role, host in local.inventory_hosts :
    role => {
      name         = host
      private_ip   = local.private_ips[host]
      ansible_host = contains(["bastion", "nat"], role) ? local.public_ips[host] : local.private_ips[host]
    }
  }

  inventory_content = join("\n\n", [
    for role in sort(keys(local.inventory_host_records)) : join("\n", [
      "[${role}]",
      "${local.inventory_host_records[role].name} ansible_host=${local.inventory_host_records[role].ansible_host} private_ip=${local.inventory_host_records[role].private_ip}",
    ])
  ])
}
