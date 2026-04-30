output "firewall_rule_name" {
  description = "Name of the created firewall rule"
  value       = google_compute_firewall.this.name
}

output "firewall_rule_self_link" {
  description = "Self-link of the created firewall rule"
  value       = google_compute_firewall.this.self_link
}