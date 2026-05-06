output "gcp_instance_ips" {
  description = "GCP instance IP addresses"
  value       = try(module.gcp_instances[0].instance_ips, {})
}

output "aws_instance_ips" {
  description = "AWS instance IP addresses"
  value       = try(module.aws_instances[0].instance_ips, {})
}

output "hosts_file" {
  description = "Path to the generated hosts.json used by the Ansible dynamic inventory"
  value       = local_file.hosts.filename
}
