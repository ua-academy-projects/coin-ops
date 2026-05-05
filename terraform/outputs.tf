output "gcp_instance_ips" {
  description = "GCP instance IP addresses"
  value       = try(module.gcp_instances[0].instance_ips, {})
}

output "aws_instance_ips" {
  description = "AWS instance IP addresses"
  value       = try(module.aws_instances[0].instance_ips, {})
}
