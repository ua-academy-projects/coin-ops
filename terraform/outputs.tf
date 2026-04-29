output "instance_ip" {
  description = "External IP address of the EC2 instance"
  value       = google_compute_instance.jump_host.network_interface[0].access_config[0].nat_ip
}