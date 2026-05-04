output "jump_host_external_ip" {
  value       = google_compute_instance.jump_host.network_interface[0].access_config[0].nat_ip
  description = "Public IP of the jump host — SSH here first"
}

output "jump_host_internal_ip" {
  value       = google_compute_instance.jump_host.network_interface[0].network_ip
  description = "Internal IP of the jump host"
}

output "internal_vm_ips" {
  value       = [for vm in google_compute_instance.internal_vm : vm.network_interface[0].network_ip]
  description = "Internal IPs of the 3 private VMs"
}

output "ssh_port" {
  value       = var.ssh_port
  description = "SSH port used by all VMs"
}

output "ops_user" {
  value       = var.ops_user
  description = "Operational user for SSH access"
}