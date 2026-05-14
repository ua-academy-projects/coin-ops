locals {
  inventory_ssh_user = local.config.cloud == "aws" ? try(local.config.project.aws.ansible_user, "ubuntu") : local.config.ssh.user
  active_infra       = local.config.cloud == "aws" ? module.aws_infra[0] : module.gcp_infra[0]
  proxy_command      = "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ${local.inventory_ssh_user}@${local.active_infra.bastion_external_ip}"
  ssh_common_args    = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand=\"${local.proxy_command}\""

  inventory_groups = {
    db      = try(local.active_infra.private_internal_ips["db"], null)
    history = try(local.active_infra.private_internal_ips["app"], null)
    proxy   = try(local.active_infra.private_internal_ips["app"], null)
    ui      = try(local.active_infra.private_internal_ips["web"], null)
  }
}

resource "local_file" "ansible_inventory" {
  filename = var.inventory_output_path
  content = templatefile("${path.module}/templates/inventory.tftpl", {
    cloud              = upper(local.config.cloud)
    root_module_path   = abspath(path.module)
    inventory_ssh_user = local.inventory_ssh_user
    ssh_common_args    = local.ssh_common_args
    inventory_groups   = local.inventory_groups
  })
}
