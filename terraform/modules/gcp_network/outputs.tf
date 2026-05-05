output "network_id" {
  value = google_compute_network.vpc.id
}

output "subnet_ids" {
  value = { for name, subnet in google_compute_subnetwork.subnet : name => subnet.id }
}
