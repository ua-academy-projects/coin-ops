output "dns_name" {
  value = try(aws_elb.web[0].dns_name, null)
}

output "ip_address" {
  value = try(google_compute_forwarding_rule.web[0].ip_address, null)
}
