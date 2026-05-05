locals {
  runtime_instances = {
    for name, instance in module.vms.instances : name => {
      name       = instance.name
      role       = local.config.instances[name].role
      private_ip = instance.internal_ip
      public_ip  = instance.external_ip
    }
  }

  bastion = local.runtime_instances[local.config.app.nodes.bastion]

  ssh_config = join("\n\n", concat(
    [<<-EOT
    Host ${local.name_prefix}-bastion
      HostName ${local.bastion.public_ip}
      User ${local.config.ssh.user}
      IdentityFile ${local.config.ssh.private_key_path}
      IdentitiesOnly yes
      UserKnownHostsFile ~/.ssh/known_hosts_gcp_lab
      StrictHostKeyChecking accept-new
    EOT
    ],
    [
      for name, instance in local.runtime_instances : <<-EOT
      Host ${local.name_prefix}-${name}
        HostName ${instance.private_ip}
        User ${local.config.ssh.user}
        IdentityFile ${local.config.ssh.private_key_path}
        IdentitiesOnly yes
        ProxyJump ${local.name_prefix}-bastion
        UserKnownHostsFile ~/.ssh/known_hosts_gcp_lab
        StrictHostKeyChecking accept-new
      EOT
      if name != local.config.app.nodes.bastion
    ]
  ))
}

output "app_url" {
  value = null
}

output "bastion_public_ip" {
  value = local.bastion.public_ip
}

output "instances" {
  value = local.runtime_instances
}

output "ssh_config" {
  value = local.ssh_config
}

output "ansible_inventory" {
  value = ""
}
