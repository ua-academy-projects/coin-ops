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

output "api_endpoint" {
  value = local.k3s_only ? "" : module.load_balancer[0].public_ip_address
}

output "key_vault_id" {
  value = module.secrets.key_vault_id
}

output "resource_group_name" {
  value = module.network.resource_group_name
}

output "location" {
  value = module.network.location
}

output "monitoring_targets" {
  value = {
    virtual_machines = module.compute.monitoring_targets
    nat_gateway_id   = module.network.nat_gateway_id
    key_vault_id     = module.secrets.key_vault_id
  }
}
