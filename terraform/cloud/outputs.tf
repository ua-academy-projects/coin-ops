output "instance_names" {
  value = merge(
    try(module.gcp_instances[0].instance_names, {}),
    try(module.azure_instances[0].instance_names, {}),
    try(module.aws_instances[0].instance_names, {})
  )
}


output "private_ips" {
  value = merge(
    try(module.gcp_instances[0].private_ips, {}),
    try(module.azure_instances[0].private_ips, {}),
    try(module.aws_instances[0].private_ips, {})
  )
}


output "public_ips" {
  value = merge(
    try(module.gcp_instances[0].public_ips, {}),
    try(module.azure_instances[0].public_ips, {}),
    try(module.aws_instances[0].public_ips, {})
  )
}

output "ansible_inventory_path" {
  value = local_file.ansible_inventory.filename
}

output "aks_cluster_name" {
  value = try(module.azure_aks[0].name, null)
}

output "aks_resource_group_name" {
  value = try(module.azure_aks[0].resource_group_name, null)
}

output "aks_kube_config_raw" {
  value     = try(module.azure_aks[0].kube_config_raw, null)
  sensitive = true
}

output "jenkins_namespace" {
  value = try(module.jenkins[0].namespace, null)
}

output "jenkins_release_name" {
  value = try(module.jenkins[0].release_name, null)
}

output "jenkins_status" {
  value = try(module.jenkins[0].status, null)
}

output "cloud_sql_instance_name" {
  value = local.default_cloud == "gcp" ? try(module.gcp_sql[0].instance_name, null) : (
    local.default_cloud == "azure" ? try(module.azure_sql[0].instance_name, null) : (
      local.default_cloud == "aws" ? try(module.aws_sql[0].instance_name, null) : null
    )
  )
}

output "external_db_host" {
  value = local.default_cloud == "gcp" ? try(module.gcp_sql[0].private_endpoint, null) : (
    local.default_cloud == "azure" ? try(module.azure_sql[0].private_endpoint, null) : (
      local.default_cloud == "aws" ? try(module.aws_sql[0].private_endpoint, null) : null
    )
  )
}

output "cloud_sql_connection_name" {
  value = local.default_cloud == "gcp" ? try(module.gcp_sql[0].connection_name, null) : (
    local.default_cloud == "azure" ? try(module.azure_sql[0].connection_name, null) : (
      local.default_cloud == "aws" ? try(module.aws_sql[0].connection_name, null) : null
    )
  )
}

output "cloud_sql_database_name" {
  value = local.default_cloud == "gcp" ? try(module.gcp_sql[0].database_name, null) : (
    local.default_cloud == "azure" ? try(module.azure_sql[0].database_name, null) : (
      local.default_cloud == "aws" ? try(module.aws_sql[0].database_name, null) : null
    )
  )
}

output "cloud_sql_database_user" {
  value = local.default_cloud == "gcp" ? try(module.gcp_sql[0].database_user, null) : (
    local.default_cloud == "azure" ? try(module.azure_sql[0].database_user, null) : (
      local.default_cloud == "aws" ? try(module.aws_sql[0].database_user, null) : null
    )
  )
}

output "monitoring_workspace_name" {
  value = try(module.azure_monitoring[0].workspace_name, null)
}

output "monitoring_application_insights_id" {
  value = try(module.azure_monitoring[0].application_insights_id, null)
}

output "monitoring_vm_cpu_alert_names" {
  value = try(module.azure_monitoring[0].vm_cpu_alert_names, {})
}

output "monitoring_postgresql_alert_names" {
  value = try(module.azure_monitoring[0].postgresql_alert_names, {})
}

output "monitoring_availability_test_names" {
  value = try(module.azure_monitoring[0].availability_test_names, {})
}
