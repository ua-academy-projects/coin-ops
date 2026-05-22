locals {
  backend_app_url           = local.is_aws ? module.aws[0].app_url : local.is_gcp ? module.gcp[0].app_url : module.azure[0].app_url
  backend_bastion_public_ip = local.is_aws ? module.aws[0].bastion_public_ip : local.is_gcp ? module.gcp[0].bastion_public_ip : module.azure[0].bastion_public_ip
  backend_instances         = local.is_aws ? module.aws[0].instances : local.is_gcp ? module.gcp[0].instances : module.azure[0].instances
  backend_ssh_config        = local.is_aws ? module.aws[0].ssh_config : local.is_gcp ? module.gcp[0].ssh_config : module.azure[0].ssh_config
  backend_ansible_inventory = local.is_aws ? module.aws[0].ansible_inventory : local.is_gcp ? module.gcp[0].ansible_inventory : module.azure[0].ansible_inventory
  backend_load_balancer     = local.is_aws ? module.aws[0].load_balancer : local.is_gcp ? module.gcp[0].load_balancer : module.azure[0].load_balancer
  backend_runtime           = local.is_aws ? module.aws[0].runtime : local.is_gcp ? module.gcp[0].runtime : module.azure[0].runtime
  backend_secret_refs       = local.is_aws ? module.aws[0].secret_refs : local.is_gcp ? module.gcp[0].secret_refs : module.azure[0].secret_refs

  # backend_load_balancer is null in k3s-only mode (no LB built), so guard
  # the dereference.
  backend_endpoint      = local.is_azure ? module.azure[0].api_endpoint : try(local.backend_load_balancer.dns_name, "")
  backend_endpoint_type = local.is_aws ? "CNAME" : "A"

  split_aws_ui = local.split_ui_backend && local.ui_cloud == "aws"
  split_gcp_ui = local.split_ui_backend && local.ui_cloud == "gcp"

  ui_endpoint      = local.split_aws_ui ? module.aws_ui[0].endpoint : local.split_gcp_ui ? module.gcp_ui[0].endpoint : local.backend_endpoint
  ui_endpoint_type = local.split_aws_ui ? module.aws_ui[0].endpoint_type : local.split_gcp_ui ? module.gcp_ui[0].endpoint_type : local.backend_endpoint_type
  ui_instances     = local.split_aws_ui ? module.aws_ui[0].instances : local.split_gcp_ui ? module.gcp_ui[0].instances : {}
  ui_ssh_config    = local.split_aws_ui ? module.aws_ui[0].ssh_config : local.split_gcp_ui ? module.gcp_ui[0].ssh_config : ""
  ui_inventory     = local.split_aws_ui ? module.aws_ui[0].ansible_inventory : local.split_gcp_ui ? module.gcp_ui[0].ansible_inventory : ""

  app_url = try(local.config.domain.enabled, false) && local.stack.ui.domain != "" ? "https://${local.stack.ui.domain}" : (
    local.split_ui_backend ? "http://${local.ui_endpoint}" : local.backend_app_url
  )
  api_url = try(local.config.domain.enabled, false) && local.stack.api.domain != "" ? "https://${local.stack.api.domain}" : local.backend_app_url
}

output "app_url" {
  value = local.app_url
}

output "api_url" {
  value = local.api_url
}

output "ui_endpoint" {
  value = local.ui_endpoint
}

output "api_endpoint" {
  value = local.backend_endpoint
}

output "bastion_public_ip" {
  value = local.backend_bastion_public_ip
}

output "instances" {
  value = merge(local.backend_instances, local.ui_instances)
}

output "ssh_config" {
  value = trimspace(join("\n\n", compact([
    local.backend_ssh_config,
    local.ui_ssh_config,
  ])))
}

output "ansible_inventory" {
  value = trimspace(join("\n", compact([
    local.backend_ansible_inventory,
    local.ui_inventory,
  ])))
}

output "load_balancer" {
  value = merge(local.backend_load_balancer == null ? {} : local.backend_load_balancer, {
    ui_endpoint  = local.ui_endpoint
    api_endpoint = local.backend_endpoint
  })
}

output "runtime" {
  value = local.backend_runtime
}

output "secret_refs" {
  value = local.backend_secret_refs
}

output "db_password_secret_ref" {
  value = try(local.backend_secret_refs.db_password, null)
}

output "rabbitmq_password_secret_ref" {
  value = try(local.backend_secret_refs.rabbitmq_password, null)
}

output "ghcr_token_secret_ref" {
  value = try(local.backend_secret_refs.ghcr_token, null)
}
