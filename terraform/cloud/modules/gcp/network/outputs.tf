# outputs.tf

output "network_name" {
  value = google_compute_network.coinops.name
}


output "subnetwork_names" {
  value = { for key, subnet in google_compute_subnetwork.coinops : key => subnet.name }
}
