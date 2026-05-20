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

output "cloud_sql_instance_name" {
  value = var.cloud == "gcp" ? try(module.gcp_sql[0].instance_name, null) : (
    var.cloud == "azure" ? try(module.azure_sql[0].instance_name, null) : null
  )
}

output "external_db_host" {
  value = var.cloud == "gcp" ? try(module.gcp_sql[0].private_ip, null) : (
    var.cloud == "azure" ? try(module.azure_sql[0].private_fqdn, null) : null
  )
}

output "cloud_sql_connection_name" {
  value = var.cloud == "gcp" ? try(module.gcp_sql[0].connection_name, null) : (
    var.cloud == "azure" ? try(module.azure_sql[0].private_fqdn, null) : null
  )
}

output "cloud_sql_database_name" {
  value = var.cloud == "gcp" ? try(module.gcp_sql[0].database_name, null) : (
    var.cloud == "azure" ? try(module.azure_sql[0].database_name, null) : null
  )
}

output "cloud_sql_database_user" {
  value = var.cloud == "gcp" ? try(module.gcp_sql[0].database_user, null) : (
    var.cloud == "azure" ? try(module.azure_sql[0].database_user, null) : null
  )
}
