locals {

  supported_clouds = ["gcp", "azure", "aws"]

  default_cloud  = var.cloud
  security_rules = coalesce(var.security_rules, {})
  secrets        = coalesce(var.secrets, {})

  # add default cloud values, if no one specified
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


  # puts networks in cloud buckets
  networks_grouped_by_cloud = {
    for cloud in local.supported_clouds : cloud => [
      for _, network in local.networks : network
      if network.cloud == cloud
    ]
  }


  # turns networks lists per cloud into network objects
  networks_by_cloud = {
    for cloud, networks in local.networks_grouped_by_cloud :
    cloud => length(networks) == 1 ? networks[0] : null
  }


  # split workloads by cloud before sending them to cloud modules
  workloads_by_cloud = {
    for cloud in local.supported_clouds : cloud => {
      for name, workload in local.workloads : name => workload
      if workload.cloud == cloud
    }
  }

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


  # shared instance outputs from all enabled clouds
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

  # inventory roles
  inventory_role_names = sort(distinct(flatten([
    for _, workload in local.workloads : workload.roles
  ])))

  # private hosts connect through the public bastion when it exists
  inventory_bastion_host = try(one([
    for name, workload in local.workloads : name
    if contains(workload.roles, "bastion")
  ]), null)

  inventory_bastion_host_public_ip = local.inventory_bastion_host != null ? try(local.public_ips[local.inventory_bastion_host], null) : null

  # inventory hosts
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

  # inventory groups
  inventory_role_members = {
    for role in local.inventory_role_names :
    role => [
      for name, host in local.inventory_hosts : name
      if contains(host.roles, role)
    ]
  }

  # rendered inventory file for ansible
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
