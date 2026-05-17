output "network_id" {
  description = "ID of the VPC network"
  value       = google_compute_network.this.id
}

output "network_self_link" {
  description = "Self-link of the VPC network"
  value       = google_compute_network.this.self_link
}

output "network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.this.name
}

output "subnet_ids" {
  description = "Map of subnet name to subnet ID"
  value       = { for k, v in google_compute_subnetwork.this : k => v.id }
}

output "subnet_self_links" {
  description = "Map of subnet name to subnet self_link"
  value       = { for k, v in google_compute_subnetwork.this : k => v.self_link }
}

output "subnet_cidrs" {
  description = "Map of subnet name to CIDR range"
  value       = { for k, v in google_compute_subnetwork.this : k => v.ip_cidr_range }
}
