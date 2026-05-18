output "jump_host_external_ip" {
  description = "Public IP address of the jump host — use this for SSH access"
  value = local.general.cloud == "gcp" ? module.gcp_vm.jump_host_external_ip : (
    local.general.cloud == "aws" ? module.aws_vm.jump_host_external_ip :
    module.azure_vm.jump_host_external_ip
  )
}

output "jump_host_internal_ip" {
  description = "Internal IP address of the jump host within the VPC"
  value = local.general.cloud == "gcp" ? module.gcp_vm.jump_host_internal_ip : (
    local.general.cloud == "aws" ? module.aws_vm.jump_host_internal_ip :
    module.azure_vm.jump_host_internal_ip
  )
}

output "internal_vm_ips" {
  description = "Internal IP addresses of all internal nodes"
  value = local.general.cloud == "gcp" ? module.gcp_vm.internal_vm_ips : (
    local.general.cloud == "aws" ? module.aws_vm.internal_vm_ips :
    module.azure_vm.internal_vm_ips
  )
}

output "ssh_connection" {
  description = "Ready-to-use SSH command to connect to the jump host"
  value = "ssh -p ${local.general.ssh_port} ${local.general.ops_user}@${
    local.general.cloud == "gcp" ? module.gcp_vm.jump_host_external_ip : (
    local.general.cloud == "aws" ? module.aws_vm.jump_host_external_ip :
    module.azure_vm.jump_host_external_ip)
  }"
}

output "rds_endpoint" {
  description = "AWS RDS PostgreSQL connection endpoint (AWS only)"
  value       = local.general.cloud == "aws" ? module.aws_rds.db_endpoint : null
}

output "rds_db_name" {
  description = "AWS RDS database name (AWS only)"
  value       = local.general.cloud == "aws" ? module.aws_rds.db_name : null
}

output "alb_dns_name" {
  description = "DNS name of the AWS Application Load Balancer (AWS only)"
  value       = local.general.cloud == "aws" ? module.aws_lb.alb_dns_name : null
}

output "gcp_lb_ip" {
  description = "Public IP of GCP Load Balancer (GCP only)"
  value       = local.general.cloud == "gcp" ? module.gcp_lb.lb_ip : null
}

output "gcp_db_endpoint" {
  description = "CloudSQL private IP (GCP only)"
  value       = local.general.cloud == "gcp" ? module.gcp_sql.db_endpoint : null
}

output "azure_lb_ip" {
  description = "Public IP of Azure Load Balancer (Azure only)"
  value       = local.general.cloud == "azure" ? module.azure_lb.lb_public_ip : null
}

output "azure_db_endpoint" {
  description = "Azure PostgreSQL Flexible Server FQDN (Azure only)"
  value       = local.general.cloud == "azure" ? module.azure_db.db_endpoint : null
}