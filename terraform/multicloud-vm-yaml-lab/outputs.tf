output "app_url" {
  value = local.is_aws ? module.aws[0].app_url : module.gcp[0].app_url
}

output "bastion_public_ip" {
  value = local.is_aws ? module.aws[0].bastion_public_ip : module.gcp[0].bastion_public_ip
}

output "instances" {
  value = local.is_aws ? module.aws[0].instances : module.gcp[0].instances
}

output "ssh_config" {
  value = local.is_aws ? module.aws[0].ssh_config : module.gcp[0].ssh_config
}

output "ansible_inventory" {
  value = local.is_aws ? module.aws[0].ansible_inventory : module.gcp[0].ansible_inventory
}

output "load_balancer" {
  value = local.is_aws ? module.aws[0].load_balancer : null
}
