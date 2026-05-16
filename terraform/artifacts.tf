resource "local_file" "hosts" {
  filename = "${path.module}/config/hosts.json"
  content = jsonencode(merge(
    local.gcp_enabled ? {
      gcp = {
        ssh_user    = local.username
        ssh_port    = local.ssh_port
        instances   = try(module.gcp_instances[0].instance_ips, {})
        database_ip = try(module.gcp_database[0].private_ip, "")
        database = {
          host    = try(module.gcp_database[0].private_ip, "")
          port    = local.db_port
          name    = local.db_name
          user    = local.db_username
          managed = try(module.gcp_database[0].private_ip, "") != ""
        }
      }
    } : {},
    local.aws_enabled ? {
      aws = {
        ssh_user    = local.username
        ssh_port    = local.ssh_port
        instances   = try(module.aws_instances[0].instance_ips, {})
        database_ip = try(module.aws_database[0].address, "")
        database = {
          host    = try(module.aws_database[0].address, "")
          port    = try(module.aws_database[0].port, local.db_port)
          name    = local.db_name
          user    = local.db_username
          managed = try(module.aws_database[0].address, "") != ""
        }
      }
    } : {}
  ))
}

resource "local_file" "ssh_config" {
  filename = "${path.module}/config/ssh_config"
  content = trimspace(join("\n\n", concat(
    local.gcp_enabled ? [
      for name, inst in local.gcp_hosts : trimspace(<<-EOT
        Host coinops-gcp-${name}
          HostName ${inst.role == "jump-host" ? inst.public_ip : inst.private_ip}
          User ${local.username}
          Port ${local.ssh_port}
          ${inst.role != "jump-host" && local.gcp_jump_host_name != "" ? "ProxyJump coinops-gcp-${local.gcp_jump_host_name}" : ""}
          IdentityFile ${pathexpand(replace(var.ssh_public_key_path, ".pub", ""))}
          IdentitiesOnly yes
          ServerAliveInterval 15
          ServerAliveCountMax 4
          ConnectionAttempts 3
          ConnectTimeout 20
          ControlMaster no
          StrictHostKeyChecking no
          UserKnownHostsFile /dev/null
      EOT
      )
    ] : [],
    local.aws_enabled ? [
      for name, inst in local.aws_hosts : trimspace(<<-EOT
        Host coinops-aws-${name}
          HostName ${inst.role == "jump-host" ? inst.public_ip : inst.private_ip}
          User ${local.username}
          Port ${local.ssh_port}
          ${inst.role != "jump-host" && local.aws_jump_host_name != "" ? "ProxyJump coinops-aws-${local.aws_jump_host_name}" : ""}
          IdentityFile ${pathexpand(replace(var.ssh_public_key_path, ".pub", ""))}
          IdentitiesOnly yes
          ServerAliveInterval 15
          ServerAliveCountMax 4
          ConnectionAttempts 3
          ConnectTimeout 20
          ControlMaster no
          StrictHostKeyChecking no
          UserKnownHostsFile /dev/null
      EOT
      )
    ] : []
  )))
}

resource "local_file" "ansible_runtime" {
  filename = "${path.module}/config/ansible-runtime.json"
  content = jsonencode(merge(
    local.gcp_enabled ? {
      gcp = {
        database_ip    = try(module.gcp_database[0].private_ip, "")
        use_managed_db = try(module.gcp_database[0].private_ip, "") != ""
        database = {
          host    = try(module.gcp_database[0].private_ip, "")
          port    = local.db_port
          name    = local.db_name
          user    = local.db_username
          managed = try(module.gcp_database[0].private_ip, "") != ""
        }
      }
    } : {},
    local.aws_enabled ? {
      aws = {
        database_ip    = try(module.aws_database[0].address, "")
        use_managed_db = try(module.aws_database[0].address, "") != ""
        database = {
          host    = try(module.aws_database[0].address, "")
          port    = try(module.aws_database[0].port, local.db_port)
          name    = local.db_name
          user    = local.db_username
          managed = try(module.aws_database[0].address, "") != ""
        }
      }
    } : {}
  ))
}

resource "null_resource" "sync_ssh_config" {
  triggers = {
    config_content = local_file.ssh_config.content
  }

  provisioner "local-exec" {
    command = <<EOT
      mkdir -p ~/.ssh/extra_configs
      cp ${local_file.ssh_config.filename} ~/.ssh/extra_configs/coin-ops-ssh-config
      chmod 600 ~/.ssh/extra_configs/coin-ops-ssh-config
    EOT
  }
}
