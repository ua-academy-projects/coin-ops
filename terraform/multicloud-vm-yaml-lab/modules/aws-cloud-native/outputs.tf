locals {
  bastion_instance = values(aws_instance.bastion)[0]
  db_instance      = values(aws_instance.db)[0]

  instance_outputs = merge(
    {
      for name, instance in aws_instance.bastion : name => {
        name       = "${local.name_prefix}-${name}"
        role       = "bastion"
        private_ip = instance.private_ip
        public_ip  = instance.public_ip
      }
    },
    {
      for name, instance in aws_instance.app : name => {
        name       = "${local.name_prefix}-${name}"
        role       = "app"
        private_ip = instance.private_ip
        public_ip  = instance.public_ip
      }
    },
    {
      for name, instance in aws_instance.db : name => {
        name       = "${local.name_prefix}-${name}"
        role       = "db"
        private_ip = instance.private_ip
        public_ip  = instance.public_ip
      }
    }
  )

  app_url = local.domain_enabled ? "https://${local.config.domain.name}" : "http://${aws_lb.app.dns_name}"

  ssh_bastion_alias = "${local.name_prefix}-bastion"

  ssh_config = join("\n\n", concat(
    [<<-EOT
    Host ${local.ssh_bastion_alias}
      HostName ${local.bastion_instance.public_ip}
      User ${local.ssh.user}
      IdentityFile ${local.ssh.private_key_path}
      IdentitiesOnly yes
      UserKnownHostsFile ~/.ssh/known_hosts_aws_lab
      StrictHostKeyChecking accept-new
    EOT
    ],
    [
      for name, instance in merge(aws_instance.app, aws_instance.db) : <<-EOT
      Host ${local.name_prefix}-${name}
        HostName ${instance.private_ip}
        User ${local.ssh.user}
        IdentityFile ${local.ssh.private_key_path}
        IdentitiesOnly yes
        ProxyJump ${local.ssh_bastion_alias}
        UserKnownHostsFile ~/.ssh/known_hosts_aws_lab
        StrictHostKeyChecking accept-new
      EOT
    ]
  ))

  app_inventory_lines = [
    for name, instance in aws_instance.app :
    "${local.name_prefix}-${name} ansible_host=${instance.private_ip}"
  ]

  ansible_inventory = <<-EOT
  [bastion]
  ${local.name_prefix}-${local.bastion_name} ansible_host=${local.bastion_instance.public_ip}

  [app]
  ${join("\n", local.app_inventory_lines)}

  [db]
  ${local.name_prefix}-${local.db_name} ansible_host=${local.db_instance.private_ip}

  [cloud:children]
  bastion
  app
  db

  [cloud:vars]
  coinops_ansible_user=${local.ssh.user}
  coinops_ssh_private_key_file=${local.ssh.private_key_path}
  coinops_app_domain=${local.domain_enabled ? local.config.domain.name : aws_lb.app.dns_name}
  coinops_tls_mode=off
  coinops_db_host=${local.db_instance.private_ip}
  coinops_app_url=${local.app_url}

  [bastion:vars]
  coinops_ssh_common_args='-o StrictHostKeyChecking=accept-new'

  [app:vars]
  coinops_ssh_common_args='-o ProxyJump=${local.ssh_bastion_alias} -o StrictHostKeyChecking=accept-new'

  [db:vars]
  coinops_ssh_common_args='-o ProxyJump=${local.ssh_bastion_alias} -o StrictHostKeyChecking=accept-new'
  EOT
}

output "app_url" {
  value = local.app_url
}

output "bastion_public_ip" {
  value = local.bastion_instance.public_ip
}

output "instances" {
  value = local.instance_outputs
}

output "ssh_config" {
  value = local.ssh_config
}

output "ansible_inventory" {
  value = local.ansible_inventory
}

output "load_balancer" {
  value = {
    dns_name         = aws_lb.app.dns_name
    zone_id          = aws_lb.app.zone_id
    https_enabled    = local.domain_enabled
    target_group_arn = aws_lb_target_group.app.arn
  }
}
