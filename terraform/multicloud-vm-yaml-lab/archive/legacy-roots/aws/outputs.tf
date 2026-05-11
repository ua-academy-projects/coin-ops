output "instances" {
  value = local.runtime_instances
}

output "firewall" {
  value = {
    type = "aws_security_groups"
    ids = {
      bastion = module.firewall.bastion_security_group_id
      private = module.firewall.private_security_group_id
    }
  }
}

output "bastion_public_ip" {
  value = local.runtime_instances[local.bastion_name].public_ip
}

output "private_internal_ips" {
  value = {
    for name, instance in local.private_instances :
    name => instance.private_ip
  }
}

output "ssh_config" {
  value = join("\n\n", concat(
    [
      <<-EOT
      Host ${local.ssh_bastion_alias}
        HostName ${local.runtime_instances[local.bastion_name].public_ip}
        User ${local.raw.ssh.user}
        IdentityFile ${local.raw.ssh.private_key_path}
        IdentitiesOnly yes
        UserKnownHostsFile ${local.ssh_known_hosts}
        StrictHostKeyChecking accept-new
      EOT
    ],
    [
      for name, instance in local.private_instances :
      <<-EOT
      Host ${local.raw.name_prefix}-${name}
        HostName ${instance.private_ip}
        User ${local.raw.ssh.user}
        IdentityFile ${local.raw.ssh.private_key_path}
        IdentitiesOnly yes
        ProxyJump ${local.ssh_bastion_alias}
        UserKnownHostsFile ${local.ssh_known_hosts}
        StrictHostKeyChecking accept-new
      EOT
    ]
  ))
}
