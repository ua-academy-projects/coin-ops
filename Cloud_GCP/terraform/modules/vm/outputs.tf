output "internal_ip" {
  description = "Internal IP address of the VM"
  value       = google_compute_instance.vm.network_interface[0].network_ip
}

output "external_ip" {
  description = "External IP address (null if no public IP)"
  value       = var.public_ip ? google_compute_instance.vm.network_interface[0].access_config[0].nat_ip : null
}

output "name" {
  description = "VM instance name"
  value       = google_compute_instance.vm.name
}

output "instance_id" {
  description = "GCP instance ID"
  value       = google_compute_instance.vm.instance_id
}