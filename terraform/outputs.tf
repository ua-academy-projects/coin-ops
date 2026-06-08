output "jump_host_external_ip" {
  value = local.cloud == "gcp" ? module.gcp_vm.jump_host_external_ip : (
    local.cloud == "aws" ? module.aws_vm.jump_host_external_ip : (
    local.cloud == "hybrid" ? module.aws_vm.jump_host_external_ip :
    module.azure_vm.jump_host_external_ip))
}

output "jump_host_internal_ip" {
  description = "Internal IP address of the jump host within the VPC"
  value = local.cloud == "gcp" ? module.gcp_vm.jump_host_internal_ip : (
    local.cloud == "aws" ? module.aws_vm.jump_host_internal_ip : (
    local.cloud == "hybrid" ? module.aws_vm.jump_host_internal_ip :
    module.azure_vm.jump_host_internal_ip))
}

output "internal_vm_ips" {
  description = "Internal IP addresses of all internal nodes"
  value = local.cloud == "gcp" ? module.gcp_vm.internal_vm_ips : (
    local.cloud == "aws" ? module.aws_vm.internal_vm_ips : (
    local.cloud == "hybrid" ? module.aws_vm.internal_vm_ips :
    module.azure_vm.internal_vm_ips))
}

# SSH connection string to k3s-server-1 (public node).
# In GCP-only mode there is no jump-host — connect directly to k3s-server-1.
# SSH connection string to k3s-server-1 (public node).
# In GCP-only mode there is no jump-host — connect directly to k3s-server-1.
output "ssh_connection" {
  description = "Ready-to-use SSH command to connect to the cluster entry point"
  value = "ssh -p ${local.general.ssh_port} ${local.general.ops_user}@${
    local.cloud == "gcp" ? coalesce(module.gcp_vm.jump_host_external_ip, "no-jump-host-use-k3s-server-1") : (
    local.cloud == "aws" ? coalesce(module.aws_vm.k3s_server_1_public_ip, "k3s-server-1-ip-pending") : (
    local.cloud == "hybrid" ? coalesce(module.aws_vm.jump_host_external_ip, "no-jump-host") :
    module.azure_vm.jump_host_external_ip))
  }"
}


output "rds_endpoint" {
  description = "AWS RDS PostgreSQL connection endpoint (AWS only)"
  value = contains(["aws", "hybrid"], local.cloud) ? module.aws_rds.db_endpoint : null
}

output "rds_db_name" {
  description = "AWS RDS database name (AWS only)"
  value = contains(["aws", "hybrid"], local.cloud) ? module.aws_rds.db_name : null
}

output "alb_dns_name" {
  value = local.cloud == "aws" ? module.aws_lb.alb_dns_name : null
}

output "gcp_lb_ip" {
  value = contains(["gcp", "hybrid"], local.cloud) ? module.gcp_lb.lb_ip : null
}

# Returns CloudSQL private IP after terraform apply.
# Ansible reads this value to build DATABASE_URL for Kubernetes Secrets.
output "gcp_db_endpoint" {
  value = contains(["gcp", "hybrid"], local.cloud) ? module.gcp_sql.db_endpoint : null
}

output "azure_lb_ip" {
  value = contains(["azure", "hybrid"], local.cloud) ? module.azure_lb.lb_public_ip : null
}

output "azure_db_endpoint" {
  description = "Azure PostgreSQL Flexible Server FQDN (Azure only)"
  value = contains(["azure", "hybrid"], local.cloud) ? module.azure_db.db_endpoint : null
}