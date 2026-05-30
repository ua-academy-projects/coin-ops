# outputs.tf

output "network_name" {
  value = google_compute_network.coinops.name
}

output "network_id" {
  value = google_compute_network.coinops.id
}

output "subnetwork_names" {
  value = { for key, subnet in google_compute_subnetwork.coinops : key => subnet.name }
}

output "subnetwork_ids" {
  value = { for key, subnet in google_compute_subnetwork.coinops : key => subnet.id }
}

output "private_subnet_ids" {
  value = {
    for key, subnet in google_compute_subnetwork.coinops : key => subnet.id
    if contains(keys(local.private_subnets), key)
  }
}
