locals {
  vm_ips = merge(
    length(local.aws_instances) > 0 ? module.aws[0].vm_ips : {},
    length(local.gcp_instances) > 0 ? module.gcp[0].vm_ips : {},
    length(local.azure_instances) > 0 ? module.azure[0].vm_ips : {}
  )
}

output "vm_ips" {
  value = local.vm_ips
}

output "bastion_public_ip" {
  value = contains(keys(local.vm_ips), "bastion") ? local.vm_ips["bastion"].public_ip : null
}

output "ssh_config" {
  value = length(local.vm_ips) == 0 ? "" : join("\n", concat(
    contains(keys(local.vm_ips), "bastion") ? [
      "Host coinops-bastion",
      "  HostName ${local.vm_ips["bastion"].public_ip}",
      "  User ${local.config.ssh.user}",
      "  IdentityFile ~/.ssh/id_ed25519",
      "  StrictHostKeyChecking accept-new",
      ""
    ] : [],
    [for name, vm in local.vm_ips :
      join("\n", [
        "Host coinops-${name}",
        "  HostName ${vm.private_ip}",
        "  User ${local.config.ssh.user}",
        "  IdentityFile ~/.ssh/id_ed25519",
        "  ProxyJump coinops-bastion",
        "  StrictHostKeyChecking accept-new",
        ""
      ])
      if name != "bastion"
    ]
  ))
}

output "alb_dns_name" {
  value = length(local.aws_instances) > 0 ? module.aws[0].alb_dns_name : null
}

output "rds_endpoint" {
  value = length(local.aws_instances) > 0 ? module.aws[0].rds_endpoint : null
}