output "jump_host_nsg_id" {
  description = "NSG ID for jump host"
  value       = try(azurerm_network_security_group.jump_host[0].id, null)
}

output "internal_nsg_id" {
  description = "NSG ID for internal nodes"
  value       = try(azurerm_network_security_group.internal[0].id, null)
}

output "web_nsg_id" {
  description = "NSG ID for web node"
  value       = try(azurerm_network_security_group.web[0].id, null)
}

output "db_nsg_id" {
  description = "NSG ID for database"
  value       = try(azurerm_network_security_group.db[0].id, null)
}