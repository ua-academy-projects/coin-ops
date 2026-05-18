locals {
  azure = {
    resource_group_name = var.azure_resource_group_name
    key_vault_name      = var.azure_key_vault_name
    location            = var.azure_location
  }

  normalized_secrets             = length(var.secrets) > 0 ? var.secrets : var.gsm_secrets
  normalized_workload_identities = length(var.workload_identities) > 0 ? var.workload_identities : var.service_accounts

  # Previous 5-node layout:
  # inventory_hosts = {
  #   history = "coinops-history"
  #   proxy   = "coinops-proxy"
  #   ui      = "coinops-ui"
  #   bastion = "coinops-nat"
  #   nat     = "coinops-nat"
  # }
  inventory_hosts = {
    history  = "coinops-backend"
    proxy    = "coinops-backend"
    ui       = "coinops-frontend"
    bastion  = "coinops-frontend"
    nat      = "coinops-frontend"
    backend  = "coinops-backend"
    frontend = "coinops-frontend"
  }

  private_ips = var.cloud == "gcp" ? try(module.gcp_instances[0].private_ips, {}) : (
    var.cloud == "azure" ? try(module.azure_instances[0].private_ips, {}) : try(module.aws_instances[0].private_ips, {})
  )
  public_ips = var.cloud == "gcp" ? try(module.gcp_instances[0].public_ips, {}) : (
    var.cloud == "azure" ? try(module.azure_instances[0].public_ips, {}) : try(module.aws_instances[0].public_ips, {})
  )

  # Previous 5-node inventory template:
  # inventory_content = <<-INV
  #   [history]
  #   ${local.inventory_hosts.history} ansible_host=${local.private_ips[local.inventory_hosts.history]} private_ip=${local.private_ips[local.inventory_hosts.history]}
  #
  #   [proxy]
  #   ${local.inventory_hosts.proxy} ansible_host=${local.private_ips[local.inventory_hosts.proxy]} private_ip=${local.private_ips[local.inventory_hosts.proxy]}
  #
  #   [ui]
  #   ${local.inventory_hosts.ui} ansible_host=${local.private_ips[local.inventory_hosts.ui]} private_ip=${local.private_ips[local.inventory_hosts.ui]}
  #
  #   [bastion]
  #   ${local.inventory_hosts.bastion} ansible_host=${local.public_ips[local.inventory_hosts.bastion]} private_ip=${local.private_ips[local.inventory_hosts.bastion]}
  #
  #   [nat]
  #   ${local.inventory_hosts.nat} ansible_host=${local.public_ips[local.inventory_hosts.nat]} private_ip=${local.private_ips[local.inventory_hosts.nat]}
  # INV
  inventory_content = <<-INV
    [history]
    ${local.inventory_hosts.history} ansible_host=${local.private_ips[local.inventory_hosts.history]} private_ip=${local.private_ips[local.inventory_hosts.history]}

    [proxy]
    ${local.inventory_hosts.proxy} ansible_host=${local.private_ips[local.inventory_hosts.proxy]} private_ip=${local.private_ips[local.inventory_hosts.proxy]}

    [ui]
    ${local.inventory_hosts.ui} ansible_host=${local.private_ips[local.inventory_hosts.ui]} private_ip=${local.private_ips[local.inventory_hosts.ui]}

    [bastion]
    ${local.inventory_hosts.bastion} ansible_host=${local.public_ips[local.inventory_hosts.bastion]} private_ip=${local.private_ips[local.inventory_hosts.bastion]}

    [nat]
    ${local.inventory_hosts.nat} ansible_host=${local.public_ips[local.inventory_hosts.nat]} private_ip=${local.private_ips[local.inventory_hosts.nat]}
  INV
}
