output "network_self_link" {
  value = google_compute_network.main.self_link
}

output "network_name" {
  value = google_compute_network.main.name
}

output "public_subnet_self_links" {
  value = { for key, subnet in google_compute_subnetwork.public : key => subnet.self_link }
}

output "private_subnet_self_links" {
  value = { for key, subnet in google_compute_subnetwork.private : key => subnet.self_link }
}
