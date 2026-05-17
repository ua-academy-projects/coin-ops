output "cloud" {
  description = "Selected cloud provider"
  value       = var.cloud
}

output "networks" {
  description = "Created networks"
  value = (
    var.cloud == "gcp" ? {
      for name, net in module.network_gcp : name => {
        network_name = net.network_name
        network_id   = net.network_id
        subnets      = net.subnet_cidrs
      }
    } :
    var.cloud == "aws" ? {
      for name, net in module.network_aws : name => {
        vpc_id   = net.vpc_id
        vpc_cidr = net.vpc_cidr
        subnets  = net.subnet_ids
      }
    } :
    {
      for name, net in module.network_azure : name => {
        vnet_id   = net.vnet_id
        vnet_name = net.vnet_name
        subnets   = net.subnet_ids
      }
    }
  )
}

output "vms" {
  description = "All VM details"
  value = (
    var.cloud == "gcp" ? {
      for name, vm in module.vm_gcp : name => {
        internal_ip = vm.internal_ip
        external_ip = vm.external_ip
        zone        = vm.zone
      }
    } :
    var.cloud == "aws" ? {
      for name, vm in module.vm_aws : name => {
        private_ip        = vm.private_ip
        public_ip         = vm.public_ip
        availability_zone = vm.availability_zone
      }
    } :
    {
      for name, vm in module.vm_azure : name => {
        private_ip = vm.private_ip
        public_ip  = vm.public_ip
      }
    }
  )
}

output "ssh_command" {
  description = "SSH command to connect to jump host (if exists)"
  value = try(
    var.cloud == "gcp" ?
    "ssh -A -i ~/.ssh/gcp_jump -p ${local.general.ssh_port} ${local.general.ssh_user}@${module.vm_gcp["vm-4-jump"].external_ip}" :
    var.cloud == "aws" ?
    "ssh -A -i ~/.ssh/gcp_jump -p ${local.general.ssh_port} ${local.resolved_aws_ssh_user}@${module.vm_aws["vm-4-jump"].public_ip}" :
    "ssh -A -i ~/.ssh/gcp_jump -p ${local.general.ssh_port} ${local.resolved_azure_ssh_user}@${module.vm_azure["vm-4-jump"].public_ip}",
    "Jump host not found in selected cloud"
  )
}

output "app_load_balancer_ip" {
  description = "Public IP address of the GCP application load balancer"
  value       = var.cloud == "gcp" ? try(google_compute_global_address.app_lb[0].address, null) : null
}

output "app_url" {
  description = "Public HTTPS application URL"
  value       = var.cloud == "gcp" ? "https://${var.app_domain}" : null
}

output "cloud_sql_instance_name" {
  description = "Cloud SQL PostgreSQL instance name"
  value       = var.cloud == "gcp" ? try(google_sql_database_instance.postgres[0].name, null) : null
}

output "cloud_sql_private_ip" {
  description = "Private IP address of the Cloud SQL PostgreSQL instance"
  value       = var.cloud == "gcp" ? try(google_sql_database_instance.postgres[0].private_ip_address, null) : null
}

output "db_secret_name" {
  description = "Secret Manager secret containing grouped database secrets"
  value       = var.cloud == "gcp" ? try(google_secret_manager_secret.db[0].secret_id, null) : null
}

output "service_secret_name" {
  description = "Secret Manager secret containing grouped service secrets"
  value       = var.cloud == "gcp" ? try(google_secret_manager_secret.services[0].secret_id, null) : null
}
