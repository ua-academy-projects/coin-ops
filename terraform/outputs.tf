# =============================================================================
# outputs.tf — Root Outputs
# =============================================================================
# Cloud-agnostic outputs. Same interface regardless of provider.
# =============================================================================

# ─── Provider Info ───────────────────────────────────────────────────────────
output "cloud_provider" {
  description = "Active cloud provider"
  value       = var.cloud_provider
}

output "region" {
  description = "Resolved provider-specific region"
  value       = local.region
}

# ─── Networking ──────────────────────────────────────────────────────────────
output "vpc_id" {
  description = "VPC / Network ID"
  value       = module.networking.vpc_id
}

output "vpc_name" {
  description = "VPC / Network name"
  value       = module.networking.vpc_name
}

output "subnet_ids" {
  description = "Map of subnet name → ID"
  value       = module.networking.subnet_ids
}

output "subnet_cidrs" {
  description = "Map of subnet name → CIDR"
  value       = module.networking.subnet_cidrs
}

# ─── Compute ─────────────────────────────────────────────────────────────────
output "instance_names" {
  description = "List of all VM / instance names"
  value       = module.compute.instance_names
}

output "instance_internal_ips" {
  description = "Map of instance name → internal/private IP"
  value       = module.compute.instance_ips
}

output "instance_external_ips" {
  description = "Map of instance name → external/public IP"
  value       = module.compute.instance_external_ips
}

output "bastion_external_ip" {
  description = "External IP of the bastion host"
  value = element(concat(
    [for vm_name, vm_config in local.compute_config.vms :
      lookup(module.compute.instance_external_ips, vm_name, "")
      if try(vm_config.tags["role"], "") == "bastion"
    ], ["none"]
  ), 0)
}

output "ansible_inventory_json" {
  description = "Pre-formatted dynamic inventory for Ansible"
  value = {
    for role, names in {
      for vm_name, vm_config in local.compute_config.vms :
      try(vm_config.tags["role"], "ungrouped") => vm_name...
    } : role => { hosts = names }
  }
}

# ─── State Info ──────────────────────────────────────────────────────────────
output "terraform_state_location" {
  description = "Where Terraform state is stored"
  value = (
    local.is_gcp
    ? "gs://${var.state_bucket}/terraform/state"
    : "s3://${var.state_bucket}/terraform/state"
  )
}

# ─── Load Balancer ───────────────────────────────────────────────────────────
output "lb_ip" {
  description = "External IP/DNS of the load balancer"
  value       = module.load_balancer.lb_ip
}

output "lb_id" {
  description = "ID or ARN of the load balancer"
  value       = module.load_balancer.lb_id
}

output "lb_aws_acm_validation_records" {
  description = "DNS records required to validate the AWS ACM certificate for the LB"
  value       = module.load_balancer.aws_acm_validation_records
}

# ─── Database ────────────────────────────────────────────────────────────────
output "db_instance_address" {
  description = "Database instance address"
  value       = module.db.db_instance_address
}

output "db_instance_port" {
  description = "Database instance port"
  value       = module.db.db_instance_port
}

output "db_connection_string" {
  description = "Database connection string"
  value       = module.db.db_connection_string
  sensitive   = true
}

output "db_password" {
  description = "Database password"
  value       = module.db.db_password
  sensitive   = true
}
