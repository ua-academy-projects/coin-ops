output "app_url" {
  value = module.access_outputs.app_url
}

output "bastion_public_ip" {
  value = module.access_outputs.bastion_public_ip
}

output "instances" {
  value = module.access_outputs.instances
}

output "ssh_config" {
  value = module.access_outputs.ssh_config
}

output "ansible_inventory" {
  value = module.access_outputs.ansible_inventory
}

output "load_balancer" {
  value = module.access_outputs.load_balancer
}


output "runtime" {
  value = module.access_outputs.runtime
}

output "secret_refs" {
  value = module.access_outputs.secret_refs
}