output "network_name" {
  description = "Name of the VPC network"
  value       = google_compute_network.vpc.name
}

output "subnet_cidr" {
  description = "CIDR range of the subnet"
  value       = google_compute_subnetwork.subnet.ip_cidr_range
}

output "internal_vm_names" {
  description = "Names of internal VMs"
  value       = google_compute_instance.internal_vm[*].name
}

output "internal_vm_ips" {
  description = "Internal IPs of VMs 1-3"
  value       = google_compute_instance.internal_vm[*].network_interface[0].network_ip
}

output "jump_host_name" {
  description = "Name of the jump host"
  value       = google_compute_instance.jump_host.name
}

output "jump_host_internal_ip" {
  description = "Internal IP of the jump host"
  value       = google_compute_instance.jump_host.network_interface[0].network_ip
}

output "jump_host_external_ip" {
  description = "External (public) IP of the jump host"
  value       = google_compute_instance.jump_host.network_interface[0].access_config[0].nat_ip
}