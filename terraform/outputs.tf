output "jump_host_external_ip" {
  description = "Public IP address of the jump host — use this for SSH access"
  value       = local.general.cloud == "gcp" ? module.gcp_vm.jump_host_external_ip : module.aws_vm.jump_host_external_ip
}

output "jump_host_internal_ip" {
  description = "Internal IP address of the jump host within the VPC"
  value       = local.general.cloud == "gcp" ? module.gcp_vm.jump_host_internal_ip : module.aws_vm.jump_host_internal_ip
}

output "internal_vm_ips" {
  description = "Internal IP addresses of all internal nodes (node-01, node-02, node-03)"
  value       = local.general.cloud == "gcp" ? module.gcp_vm.internal_vm_ips : module.aws_vm.internal_vm_ips
}

output "ssh_connection" {
  description = "Ready-to-use SSH command to connect to the jump host"
  value       = "ssh -p ${local.general.ssh_port} ${local.general.ops_user}@${local.general.cloud == "gcp" ? module.gcp_vm.jump_host_external_ip : module.aws_vm.jump_host_external_ip}"
}

output "rds_endpoint" {
  description = "AWS RDS PostgreSQL connection endpoint (AWS only, null on GCP)"
  value       = local.general.cloud == "aws" ? module.aws_rds.db_endpoint : null
}

output "rds_db_name" {
  description = "AWS RDS database name (AWS only, null on GCP)"
  value       = local.general.cloud == "aws" ? module.aws_rds.db_name : null
}

output "alb_dns_name" {
  description = "DNS name of the AWS Application Load Balancer (AWS only, null on GCP)"
  value       = local.general.cloud == "aws" ? module.aws_lb.alb_dns_name : null
}

output "gcp_lb_ip" {
  description = "Public IP of GCP Load Balancer (GCP only, null on AWS)"
  value       = local.general.cloud == "gcp" ? module.gcp_lb.lb_ip : null
}

output "gcp_db_endpoint" {
  description = "CloudSQL private IP (GCP only, null on AWS)"
  value       = local.general.cloud == "gcp" ? module.gcp_sql.db_endpoint : null
}