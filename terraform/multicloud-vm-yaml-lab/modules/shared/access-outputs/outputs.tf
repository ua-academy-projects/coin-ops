output "app_url" {
  value = var.app_url
}

output "bastion_public_ip" {
  value = local.bastion.public_ip
}

output "instances" {
  value = var.instances
}

output "ssh_config" {
  value = local.ssh_config
}

output "ansible_inventory" {
  value = local.ansible_inventory
}

output "load_balancer" {
  value = var.load_balancer
}

output "runtime" {
  value = var.runtime
}

output "secret_refs" {
  value = var.secret_refs
}