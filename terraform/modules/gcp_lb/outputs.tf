output "lb_ip" {
  description = "Public IP of the GCP Load Balancer"
  value       = try(google_compute_global_forwarding_rule.ui[0].ip_address, null)
}