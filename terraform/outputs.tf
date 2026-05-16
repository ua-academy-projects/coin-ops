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

output "public_endpoints" {
  description = "Cloud-specific public UI endpoints. DNS is created only for dns.primary_cloud; non-primary clouds are tested by direct public IP."
  value = {
    for cloud, ip in local.ui_public_ips : cloud => {
      public_ip  = ip
      direct_url = format("https://%s", ip)
      dns_name   = cloud == local.dns_primary_cloud ? local.app_domain : null
      dns_url    = cloud == local.dns_primary_cloud ? format("https://%s", local.app_domain) : null
    }
    if lookup(local.cloud_has_ui, cloud, false)
  }
}

output "control_plane_cloud" {
  description = "Cloud selected in JSON as the intended Terraform control plane. The active backend is generated into backend.active.tf by bootstrap."
  value       = local.control_plane_cloud
}
