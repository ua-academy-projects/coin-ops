output "gcp_instance_ips" {
  description = "GCP instance IP addresses"
  value       = try(module.gcp_instances[0].instance_ips, {})
}

output "aws_instance_ips" {
  description = "AWS instance IP addresses"
  value       = try(module.aws_instances[0].instance_ips, {})
}

output "hosts_file" {
  description = "Path to the generated hosts.json artifact for operator/debugging use"
  value       = local_file.hosts.filename
}

output "ssh_config_file" {
  description = "Path to generated SSH config with bastion and private hosts"
  value       = local_file.ssh_config.filename
}

output "ansible_runtime_file" {
  description = "Path to the generated non-secret Terraform-to-Ansible runtime metadata"
  value       = local_file.ansible_runtime.filename
}
