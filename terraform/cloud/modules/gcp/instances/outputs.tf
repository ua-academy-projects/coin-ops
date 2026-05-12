# outputs.tf

output "instance_names" {
  value = { for key, instance in google_compute_instance.this : key => instance.name }
}


output "private_ips" {
  value = { for key, instance in google_compute_instance.this : key => instance.network_interface[0].network_ip }
}


output "public_ips" {
  value = { for key, instance in google_compute_instance.this : key => try(instance.network_interface[0].access_config[0].nat_ip, null) }
}

output "instance_self_links" {
  value = { for key, instance in google_compute_instance.this : key => instance.self_link }
}


output "workload_tags" {
  value = { for key, instance in local.instances : key => instance.tags }
}


output "workload_selectors" {
  value = local.workload_selectors
}

output "service_accounts" {
  value = {
    for key, account in google_service_account.this : key => {
      email = account.email
    }
  }
}
