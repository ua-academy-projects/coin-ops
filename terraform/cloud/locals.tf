locals {
  # ------------------------------------------------------------
  # Shared Defaults
  # ------------------------------------------------------------
  supported_clouds = ["gcp", "azure", "aws"]
  default_cloud    = var.cloud

  # ------------------------------------------------------------
  # Cloud-Normalized Inputs
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

  # ------------------------------------------------------------
  # Per-Cloud Buckets
  # ------------------------------------------------------------
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
  enable_azure_routing   = local.azure_nat_route != null

  enable_gcp_network   = local.networks_by_cloud.gcp != null
  enable_gcp_workloads = local.enable_gcp_network && length(local.workloads_by_cloud.gcp) > 0
  enable_gcp_security  = local.enable_gcp_workloads && length(var.security_rules) > 0 && local.default_cloud == "gcp"
  enable_gcp_secrets   = local.enable_gcp_workloads && length(var.secrets) > 0 && local.default_cloud == "gcp"
  enable_gcp_sql       = local.enable_gcp_network && var.sql != null && local.default_cloud == "gcp"

  enable_aws_network   = local.networks_by_cloud.aws != null
  enable_aws_workloads = local.enable_aws_network && length(local.workloads_by_cloud.aws) > 0
  enable_aws_security  = local.enable_aws_workloads && length(var.security_rules) > 0 && local.default_cloud == "aws"
  enable_aws_sql       = local.enable_aws_network && var.sql != null && local.default_cloud == "aws"

  # ------------------------------------------------------------
  # Validation Helpers
  # ------------------------------------------------------------
  network_clouds_with_multiple_networks = [
    for cloud, networks in local.networks_grouped_by_cloud : cloud
    if length(networks) > 1
  ]

  workload_clouds_without_network = distinct([
    for _, workload in local.workloads : workload.cloud
    if try(local.networks_by_cloud[workload.cloud], null) == null
  ])

  invalid_workload_subnet_refs = [
    for name, workload in local.workloads : name
    if try(local.networks_by_cloud[workload.cloud].subnets[workload.subnet], null) == null
  ]

  # ------------------------------------------------------------
  # NAT Route Shapes
  # ------------------------------------------------------------
  azure_nat_route = local.default_cloud == "azure" && length(local.workloads_by_cloud.azure) > 0 && var.nat_route != null ? {
    name              = var.nat_route.name
    destination_range = var.nat_route.destination_range
    next_hop_ip       = module.azure_instances[0].private_ips[var.nat_route.instance_workload]
  } : null

  gcp_nat_route = local.default_cloud == "gcp" && length(local.workloads_by_cloud.gcp) > 0 && var.nat_route != null ? {
    name              = var.nat_route.name
    destination_range = var.nat_route.destination_range
    target_tags       = var.nat_route.target_tags
    next_hop_instance = module.gcp_instances[0].instance_self_links[var.nat_route.instance_workload]
  } : null

  aws_nat_route = local.default_cloud == "aws" && length(local.workloads_by_cloud.aws) > 0 && var.nat_route != null ? {
    name              = var.nat_route.name
    destination_range = var.nat_route.destination_range
    next_hop_instance = module.aws_instances[0].network_interface_ids[var.nat_route.instance_workload]
  } : null

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

  inventory_bastion_host_public_ip = local.inventory_bastion_host != null ? try(local.public_ips[local.inventory_bastion_host], null) : null

  inventory_hosts = {
    for name, workload in local.workloads : name => {
      cloud                   = workload.cloud
      roles                   = workload.roles
      private_ip              = try(local.private_ips[name], "")
      public_ip               = try(local.public_ips[name], null)
      ansible_host            = try(local.public_ips[name], null) != null ? local.public_ips[name] : try(local.private_ips[name], "")
      allowed_ports           = workload.allowed_ports
      required_secrets        = distinct(coalesce(try(workload.secrets, null), []))
      ansible_ssh_common_args = try(local.public_ips[name], null) == null && local.inventory_bastion_host_public_ip != null ? "-o StrictHostKeyChecking=accept-new -o ForwardAgent=yes -o IdentitiesOnly=yes -o ProxyCommand=\"ssh -i {{ lookup(\"env\", \"SSH_KEY_PATH\") | expanduser }} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -W %h:%p deployer@${local.inventory_bastion_host_public_ip}\"" : null
    }
  }

  inventory_role_members = {
    for role in local.inventory_role_names :
    role => [
      for name, host in local.inventory_hosts : name
      if contains(host.roles, role)
    ]
  }

  # ------------------------------------------------------------
  # Rendered Ansible Inventory
  # ------------------------------------------------------------
  inventory_content = join("\n\n", concat(
    [
      join("\n", concat(
        ["[all]"],
        [
          for host_name in sort(keys(local.inventory_hosts)) :
          trimspace(join(" ", compact([
            host_name,
            "cloud=${local.inventory_hosts[host_name].cloud}",
            "ansible_host=${local.inventory_hosts[host_name].ansible_host}",
            "private_ip=${local.inventory_hosts[host_name].private_ip}",
            local.inventory_hosts[host_name].public_ip != null ? "public_ip=${local.inventory_hosts[host_name].public_ip}" : null,
            "allowed_ports='${jsonencode(local.inventory_hosts[host_name].allowed_ports)}'",
            "required_secrets='${jsonencode(local.inventory_hosts[host_name].required_secrets)}'",
            local.inventory_hosts[host_name].ansible_ssh_common_args != null ? "ansible_ssh_common_args='${local.inventory_hosts[host_name].ansible_ssh_common_args}'" : null
          ])))
        ]
      )),
      join("\n", compact([
        "[all:vars]",
        "ansible_user=deployer",
        "ansible_ssh_private_key_file={{ lookup(\"env\", \"SSH_KEY_PATH\") | expanduser }}",
        "ansible_ssh_common_args=-o StrictHostKeyChecking=accept-new -o ForwardAgent=yes -o IdentitiesOnly=yes",
        "ansible_python_interpreter=/usr/bin/python3",
        local.inventory_bastion_host != null ? "nat_private_cidr=${local.networks_by_cloud[local.default_cloud].subnets[local.workloads[local.inventory_bastion_host].subnet].cidr}" : null
      ]))
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
