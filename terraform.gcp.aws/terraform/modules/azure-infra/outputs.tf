output "resource_group_name" {
  value = local.resource_group_name
}

output "bastion_external_ip" {
  value = try(azurerm_public_ip.vms["bastion"].ip_address, null)
}

output "bastion_internal_ip" {
  value = azurerm_network_interface.vms["bastion"].private_ip_address
}

output "private_internal_ips" {
  value = {
    app = azurerm_network_interface.vms["app"].private_ip_address
    web = azurerm_network_interface.vms["web"].private_ip_address
  }
}

output "vm_private_ips" {
  value = {
    for name, nic in azurerm_network_interface.vms : name => nic.private_ip_address
  }
}

output "vm_public_ips" {
  value = {
    for name, pip in azurerm_public_ip.vms : name => pip.ip_address
  }
}

output "load_balancer_dns_name" {
  value = null
}

output "load_balancer_ip_address" {
  value = try(azurerm_public_ip.vms["web"].ip_address, null)
}

output "external_db_host" {
  value = length(azurerm_postgresql_flexible_server.postgres) > 0 ? azurerm_postgresql_flexible_server.postgres[0].fqdn : null
}

output "network_id" {
  value = azurerm_virtual_network.main.id
}

output "subnet_ids" {
  value = {
    for name, subnet in azurerm_subnet.subnets : name => subnet.id
  }
}

output "log_analytics_workspace_id" {
  value = length(azurerm_log_analytics_workspace.main) > 0 ? azurerm_log_analytics_workspace.main[0].id : null
}

output "monitor_action_group_id" {
  value = length(azurerm_monitor_action_group.main) > 0 ? azurerm_monitor_action_group.main[0].id : null
}

output "monitoring_identity_id" {
  value = length(azurerm_user_assigned_identity.monitoring) > 0 ? azurerm_user_assigned_identity.monitoring[0].id : null
}

output "monitoring_identity_principal_id" {
  value = length(azurerm_user_assigned_identity.monitoring) > 0 ? azurerm_user_assigned_identity.monitoring[0].principal_id : null
}
