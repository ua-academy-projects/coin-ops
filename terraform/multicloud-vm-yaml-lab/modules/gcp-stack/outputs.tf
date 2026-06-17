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

output "gke" {
  value = local.gke_enabled ? {
    cluster_name        = module.gke[0].cluster_name
    location            = module.gke[0].location
    get_credentials_cmd = module.gke[0].get_credentials_command
  } : null
}

output "gke_auth" {
  sensitive = true
  value = local.gke_enabled ? {
    endpoint       = module.gke[0].endpoint
    ca_certificate = module.gke[0].ca_certificate
  } : null
}