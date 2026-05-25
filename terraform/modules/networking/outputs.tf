# =============================================================================
# modules/networking/outputs.tf
# =============================================================================
# Cloud-agnostic outputs — same interface regardless of provider.
# =============================================================================

output "vpc_id" {
  description = "VPC / Network ID"
  value = (
    var.cloud_provider == "gcp"
    ? google_compute_network.this[0].id
    : (var.cloud_provider == "aws" ? aws_vpc.this[0].id : azurerm_virtual_network.main[0].id)
  )
}

output "vpc_name" {
  description = "VPC / Network name"
  value       = var.vpc_name
}

output "subnet_ids" {
  description = "Map of subnet name → subnet ID"
  value = (
    var.cloud_provider == "gcp"
    ? { for name, subnet in google_compute_subnetwork.this : name => subnet.id }
    : (var.cloud_provider == "aws"
      ? { for name, subnet in aws_subnet.this : name => subnet.id }
    : { for name, subnet in azurerm_subnet.subnets : name => subnet.id })
  )
}

output "subnet_cidrs" {
  description = "Map of subnet name → CIDR"
  value = (
    var.cloud_provider == "gcp"
    ? { for name, subnet in google_compute_subnetwork.this : name => subnet.ip_cidr_range }
    : (var.cloud_provider == "aws"
      ? { for name, subnet in aws_subnet.this : name => subnet.cidr_block }
    : { for name, subnet in azurerm_subnet.subnets : name => tolist(subnet.address_prefixes)[0] })
  )
}

output "security_group_ids" {
  description = "Map of group name → ID (AWS SG IDs or empty map for GCP)"
  value = (
    var.cloud_provider == "aws"
    ? { for name, sg in aws_security_group.this : name => sg.id }
    : {}
  )
}

output "firewall_rule_ids" {
  description = "Map of rule name → ID (GCP firewall IDs or empty map for AWS)"
  value = (
    var.cloud_provider == "gcp"
    ? { for name, fw in google_compute_firewall.this : name => fw.id }
    : {}
  )
}

output "region" {
  description = "Resolved provider-specific region"
  value       = local.region
}

output "resource_group_name" {
  description = "Azure Resource Group Name (empty for AWS/GCP)"
  value       = var.cloud_provider == "azure" ? azurerm_resource_group.main[0].name : ""
}
