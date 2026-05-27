output "lb_ip" {
  description = "Public IP of the GCP Load Balancer"
  value       = try(google_compute_address.lb_ip[0].address, null)
}