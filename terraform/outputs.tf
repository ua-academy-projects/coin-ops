output "network_name" {
  description = "Name of the created VPC network"
  value       = google_compute_network.vpc.name
}

output "network_self_link" {
  description = "Self-link of the VPC network"
  value       = google_compute_network.vpc.self_link
}

output "subnet_name" {
  description = "Name of the created subnet"
  value       = google_compute_subnetwork.subnet.name
}

output "subnet_cidr" {
  description = "CIDR range of the subnet"
  value       = google_compute_subnetwork.subnet.ip_cidr_range
}

output "vm_name" {
  description = "Name of the test VM"
  value       = google_compute_instance.test_vm.name
}

output "vm_zone" {
  description = "Zone of the test VM"
  value       = google_compute_instance.test_vm.zone
}

output "vm_internal_ip" {
  description = "Internal IP of the test VM"
  value       = google_compute_instance.test_vm.network_interface[0].network_ip
}
