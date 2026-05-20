locals {
  azure = {
    resource_group_name = var.azure_resource_group_name
    key_vault_name      = var.azure_key_vault_name
    location            = var.azure_location
  }

  normalized_secrets = var.secrets

  private_ips = var.cloud == "gcp" ? try(module.gcp_instances[0].private_ips, {}) : (
    var.cloud == "azure" ? try(module.azure_instances[0].private_ips, {}) : try(module.aws_instances[0].private_ips, {})
  )
  public_ips = var.cloud == "gcp" ? try(module.gcp_instances[0].public_ips, {}) : (
    var.cloud == "azure" ? try(module.azure_instances[0].public_ips, {}) : try(module.aws_instances[0].public_ips, {})
  )

  inventory_role_names = ["history", "proxy", "ui", "bastion", "nat"]

  role_allowed_ports = {
    bastion = [22]
    nat     = [22]
    ui      = [22, 80, 443]
    proxy   = [22, 8080]
    history = [22, 5432, 5672, 15672, 8000]
  }

  role_required_secrets = {
    bastion = []
    nat     = []
    ui      = ["ghcr_username", "ghcr_token"]
    proxy   = ["ghcr_username", "ghcr_token", "rabbitmq_password", "db_password"]
    history = ["ghcr_username", "ghcr_token", "rabbitmq_password", "db_password"]
  }

  inventory_bastion_host = try(one([
    for name, workload in var.workloads : name
    if contains(workload.roles, "bastion")
  ]), null)

  inventory_bastion_host_public_ip = local.inventory_bastion_host != null ? try(local.public_ips[local.inventory_bastion_host], null) : null

  inventory_hosts = {
    for name, workload in var.workloads : name => {
      roles        = workload.roles
      private_ip   = local.private_ips[name]
      public_ip    = try(local.public_ips[name], null)
      ansible_host = try(local.public_ips[name], null) != null ? local.public_ips[name] : local.private_ips[name]
      allowed_ports = distinct(flatten([
        for role in workload.roles : lookup(local.role_allowed_ports, role, [])
      ]))
      required_secrets = distinct(flatten([
        for role in workload.roles : lookup(local.role_required_secrets, role, [])
      ]))
      ansible_ssh_common_args = try(local.public_ips[name], null) == null && local.inventory_bastion_host_public_ip != null ? "-o StrictHostKeyChecking=no -o ForwardAgent=yes -o ProxyJump=deployer@${local.inventory_bastion_host_public_ip}" : null
    }
  }

  inventory_role_members = {
    for role in local.inventory_role_names :
    role => [
      for name, host in local.inventory_hosts : name
      if contains(host.roles, role)
    ]
  }

  inventory_content = join("\n\n", concat(
    [
      join("\n", concat(
        ["[all]"],
        [
          for host_name in sort(keys(local.inventory_hosts)) :
          trimspace(join(" ", compact([
            host_name,
            "cloud=${var.cloud}",
            "ansible_host=${local.inventory_hosts[host_name].ansible_host}",
            "private_ip=${local.inventory_hosts[host_name].private_ip}",
            local.inventory_hosts[host_name].public_ip != null ? "public_ip=${local.inventory_hosts[host_name].public_ip}" : null,
            "allowed_ports='${jsonencode(local.inventory_hosts[host_name].allowed_ports)}'",
            "required_secrets='${jsonencode(local.inventory_hosts[host_name].required_secrets)}'",
            local.inventory_hosts[host_name].ansible_ssh_common_args != null ? "ansible_ssh_common_args='${local.inventory_hosts[host_name].ansible_ssh_common_args}'" : null
          ])))
        ]
      ))
    ],
    [
      for role in sort(keys(local.inventory_role_members)) : join("\n", concat(
        ["[${role}]"],
        local.inventory_role_members[role]
      ))
      if length(local.inventory_role_members[role]) > 0
    ]
  ))
}
