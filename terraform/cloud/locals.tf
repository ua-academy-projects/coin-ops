locals {
  # ------------------------------------------------------------
  # Shared Defaults
  # ------------------------------------------------------------
  config_path = "${path.module}/../../configs/${var.config_name}.json"
  config = jsondecode(file(local.config_path))
  supported_clouds = ["gcp", "azure", "aws"]
  default_cloud    = local.config.cloud

  # ------------------------------------------------------------
  # Cloud-Specific Resource Selection
  # ------------------------------------------------------------
  networks = {
    for name, network in var.networks : name => merge(network, {
      cloud = coalesce(network.cloud, var.cloud)
    })
  }

  workloads = {
    for name, workload in var.workloads : name => merge(workload, {
      cloud = coalesce(workload.cloud, var.cloud)
    })
  }

  networks_grouped_by_cloud = {
    for cloud in local.supported_clouds : cloud => [
      for _, network in local.networks : network
      if network.cloud == cloud
    ]
  }

  networks_by_cloud = {
    for cloud, networks in local.networks_grouped_by_cloud :
    cloud => length(networks) == 1 ? networks[0] : null
  }

  workloads_by_cloud = {
    for cloud in local.supported_clouds : cloud => {
      for name, workload in local.workloads : name => workload
      if workload.cloud == cloud
    }
  }

  # ------------------------------------------------------------
  # Module Enablement
  # ------------------------------------------------------------
  enable_azure_network   = local.networks_by_cloud.azure != null
  enable_azure_workloads = local.enable_azure_network && length(local.workloads_by_cloud.azure) > 0
  enable_azure_security  = local.enable_azure_workloads && length(var.security_rules) > 0 && local.default_cloud == "azure"
  enable_azure_sql       = local.enable_azure_network && var.sql != null && local.default_cloud == "azure"
  enable_azure_routing   = local.enable_azure_workloads && var.nat_route != null && local.default_cloud == "azure"

  enable_gcp_network   = local.networks_by_cloud.gcp != null
  enable_gcp_workloads = local.enable_gcp_network && length(local.workloads_by_cloud.gcp) > 0
  enable_gcp_security  = local.enable_gcp_workloads && length(var.security_rules) > 0 && local.default_cloud == "gcp"
  enable_gcp_secrets   = local.enable_gcp_workloads && length(var.secrets) > 0 && local.default_cloud == "gcp"
  enable_gcp_sql       = local.enable_gcp_network && var.sql != null && local.default_cloud == "gcp"
  enable_gcp_routing   = local.enable_gcp_workloads && var.nat_route != null && local.default_cloud == "gcp"

  enable_aws_network   = local.networks_by_cloud.aws != null
  enable_aws_workloads = local.enable_aws_network && length(local.workloads_by_cloud.aws) > 0
  enable_aws_security  = local.enable_aws_workloads && length(var.security_rules) > 0 && local.default_cloud == "aws"
  enable_aws_sql       = local.enable_aws_network && var.sql != null && local.default_cloud == "aws"
  enable_aws_routing   = local.enable_aws_workloads && var.nat_route != null && local.default_cloud == "aws"

  # ------------------------------------------------------------
  # Shared Instance Outputs
  # ------------------------------------------------------------
  private_ips = merge(
    try(module.gcp_instances[0].private_ips, {}),
    try(module.azure_instances[0].private_ips, {}),
    try(module.aws_instances[0].private_ips, {})
  )
  public_ips = merge(
    try(module.gcp_instances[0].public_ips, {}),
    try(module.azure_instances[0].public_ips, {}),
    try(module.aws_instances[0].public_ips, {})
  )

  # ------------------------------------------------------------
  # Inventory Model
  # ------------------------------------------------------------
  inventory_role_names = sort(distinct(flatten([
    for _, workload in local.workloads : workload.roles
  ])))

  inventory_bastion_host = try(one([
    for name, workload in local.workloads : name
    if contains(workload.roles, "bastion")
  ]), null)

  inventory_public_ips = {
    for name, ip in local.public_ips : name => ip
    if ip != null && ip != ""
  }

  inventory_bastion_host_public_ip = local.inventory_bastion_host != null ? try(local.inventory_public_ips[local.inventory_bastion_host], null) : null

  inventory_nat_target_workloads = var.nat_route != null ? [
    for name, workload in local.workloads : name
    if length(setintersection(toset(workload.tags), toset(var.nat_route.target_tags))) > 0
  ] : []

  inventory_nat_private_cidr = length(local.inventory_nat_target_workloads) > 0 ? local.networks_by_cloud[local.default_cloud].subnets[local.workloads[local.inventory_nat_target_workloads[0]].subnet].cidr : null

  inventory_default_ssh_args = "-o StrictHostKeyChecking=accept-new -o ForwardAgent=yes -o IdentitiesOnly=yes"
  inventory_proxy_ssh_args   = local.inventory_bastion_host_public_ip != null ? "${local.inventory_default_ssh_args} -o ProxyCommand=\"ssh -i {{ lookup(\"env\", \"SSH_KEY_PATH\") | expanduser }} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -W %h:%p ${var.ssh_user}@${local.inventory_bastion_host_public_ip}\"" : null

  inventory_hosts = {
    for name, workload in local.workloads : name => merge({
      cloud            = workload.cloud
      private_ip       = try(local.private_ips[name], "")
      ansible_host     = try(local.inventory_public_ips[name], null) != null ? local.inventory_public_ips[name] : try(local.private_ips[name], "")
      allowed_ports    = workload.allowed_ports
      required_secrets = distinct(coalesce(try(workload.secrets, null), []))
      }, try(local.inventory_public_ips[name], null) != null ? {
      public_ip = local.inventory_public_ips[name]
      } : {},
      try(local.inventory_public_ips[name], null) == null && local.inventory_proxy_ssh_args != null ? {
        ansible_ssh_common_args = local.inventory_proxy_ssh_args
      } : {}
    )
  }

  inventory_vars = merge({
    ansible_user                 = var.ssh_user
    ansible_ssh_private_key_file = "{{ lookup(\"env\", \"SSH_KEY_PATH\") | expanduser }}"
    ansible_ssh_common_args      = local.inventory_default_ssh_args
    ansible_python_interpreter   = "/usr/bin/python3"
    }, local.inventory_nat_private_cidr != null ? {
    nat_private_cidr = local.inventory_nat_private_cidr
  } : {})

  inventory_children = {
    for role in local.inventory_role_names : role => {
      hosts = {
        for name, workload in local.workloads : name => {}
        if contains(workload.roles, role)
      }
    }
  }

  # ------------------------------------------------------------
  # Ansible Inventory
  # ------------------------------------------------------------
  inventory = {
    all = {
      vars     = local.inventory_vars
      hosts    = local.inventory_hosts
      children = local.inventory_children
    }
  }

  inventory_content = yamlencode(local.inventory)
}
