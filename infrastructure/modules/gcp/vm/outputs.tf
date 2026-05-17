output "instance_name" {
  description = "Name of the VM instance"
  value       = google_compute_instance.this.name
}

output "instance_id" {
  description = "ID of the VM instance"
  value       = google_compute_instance.this.id
}

output "internal_ip" {
  description = "Internal IP of the VM"
  value       = google_compute_instance.this.network_interface[0].network_ip
}

output "external_ip" {
  description = "External IP of the VM (null if not assigned)"
  value       = var.assign_public_ip ? google_compute_instance.this.network_interface[0].access_config[0].nat_ip : null
}

output "self_link" {
  description = "Self-link of the VM instance"
  value       = google_compute_instance.this.self_link
}

output "zone" {
  description = "Zone of the VM instance"
  value       = google_compute_instance.this.zone
}
