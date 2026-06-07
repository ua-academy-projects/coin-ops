# locals.tf
# -> loads shared json config
#    derives cloud resources
#    renders ansible inventory

locals {


  # shared defaults

  config_path = "${path.module}/../../configs/${var.config_name}.json"
  config      = jsondecode(file(local.config_path))

  config_security_rules       = try(local.config.security_rules, {})
  config_secrets              = try(local.config.secrets, {})
  config_sql                  = try(local.config.sql, null)
  config_nat_route            = try(local.config.nat_route, null)
  config_ssh_user             = local.config.ssh.user
  config_ssh_public_key_path  = local.config.ssh.public_key_path
  config_ssh_private_key_path = local.config.ssh.private_key_path
  config_azure_resource_group = try(local.config.provider.azure.resource_group_name, var.azure_resource_group_name)
  config_azure_key_vault_name = try(local.config.provider.azure.key_vault_name, var.azure_key_vault_name)
  config_azure_location       = try(local.config.provider.azure.location, var.azure_location)

  supported_clouds = ["gcp", "azure", "aws"]
  default_cloud    = local.config.cloud


  # cloud-specific resource selection

  networks = {
    for name, network in local.config.networks : name => merge(network, {
      cloud = coalesce(try(network.cloud, null), local.config.cloud)
    })
  }

  workloads = {
    for name, workload in try(local.config.workloads, {}) : name => merge(workload, {
      cloud = coalesce(try(workload.cloud, null), local.config.cloud)
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


  # module enablement

  enable_azure_network   = local.networks_by_cloud.azure != null
  enable_azure_workloads = local.enable_azure_network && length(local.workloads_by_cloud.azure) > 0
  enable_azure_security  = local.enable_azure_workloads && length(local.config_security_rules) > 0 && local.default_cloud == "azure"
  enable_azure_sql       = local.enable_azure_network && local.config_sql != null && local.default_cloud == "azure"
  enable_azure_routing   = local.enable_azure_workloads && local.config_nat_route != null && local.default_cloud == "azure"

  enable_gcp_network   = local.networks_by_cloud.gcp != null
  enable_gcp_workloads = local.enable_gcp_network && length(local.workloads_by_cloud.gcp) > 0
  enable_gcp_security  = local.enable_gcp_workloads && length(local.config_security_rules) > 0 && local.default_cloud == "gcp"
  enable_gcp_secrets   = local.enable_gcp_workloads && length(local.config_secrets) > 0 && local.default_cloud == "gcp"
  enable_gcp_sql       = local.enable_gcp_network && local.config_sql != null && local.default_cloud == "gcp"
  enable_gcp_routing   = local.enable_gcp_workloads && local.config_nat_route != null && local.default_cloud == "gcp"

  enable_aws_network   = local.networks_by_cloud.aws != null
  enable_aws_workloads = local.enable_aws_network && length(local.workloads_by_cloud.aws) > 0
  enable_aws_security  = local.enable_aws_workloads && length(local.config_security_rules) > 0 && local.default_cloud == "aws"
  enable_aws_sql       = local.enable_aws_network && local.config_sql != null && local.default_cloud == "aws"
  enable_aws_routing   = local.enable_aws_workloads && local.config_nat_route != null && local.default_cloud == "aws"


  # shared instance outputs

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


  # inventory model

  inventory_role_names = sort(distinct(flatten([
    for _, workload in local.workloads : workload.roles
  ])))

  inventory_bastion_host = try(one([
    for name, workload in local.workloads : name
  if contains(workload.roles, "bastion")]), null)

  inventory_public_ips = {
    for name, ip in local.public_ips : name => ip
    if ip != null && ip != ""
  }

  inventory_bastion_host_public_ip = local.inventory_bastion_host != null ? try(local.inventory_public_ips[local.inventory_bastion_host], null) : null

  inventory_default_ssh_args = "-o StrictHostKeyChecking=accept-new -o ForwardAgent=yes -o IdentitiesOnly=yes"
  inventory_proxy_ssh_args   = local.inventory_bastion_host_public_ip != null ? "${local.inventory_default_ssh_args} -o ProxyCommand=\"ssh -i ${local.config_ssh_private_key_path} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -W %h:%p ${local.config_ssh_user}@${local.inventory_bastion_host_public_ip}\"" : null

  inventory_hosts = {
    for name, workload in local.workloads : name => merge({
      private_ip   = try(local.private_ips[name], "")
      ansible_host = try(local.inventory_public_ips[name], null) != null ? local.inventory_public_ips[name] : try(local.private_ips[name], "")
      }, try(local.inventory_public_ips[name], null) != null ? {
      public_ip = local.inventory_public_ips[name]
      } : {},
      try(local.inventory_public_ips[name], null) == null && local.inventory_proxy_ssh_args != null ? {
        ansible_ssh_common_args = local.inventory_proxy_ssh_args
      } : {}
    )
  }

  inventory_vars = {
    ansible_user                 = local.config_ssh_user
    ansible_ssh_private_key_file = local.config_ssh_private_key_path
    ansible_ssh_common_args      = local.inventory_default_ssh_args
    ansible_python_interpreter   = "/usr/bin/python3"
  }

  inventory_children = {
    for role in local.inventory_role_names : role => {
      hosts = {
        for name, workload in local.workloads : name => {}
        if contains(workload.roles, role)
      }
    }
  }


  # ansible inventory

  inventory = {
    all = {
      vars     = local.inventory_vars
      hosts    = local.inventory_hosts
      children = local.inventory_children
    }
  }

  inventory_content = yamlencode(local.inventory)
}
