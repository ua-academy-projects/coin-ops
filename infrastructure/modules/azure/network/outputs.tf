output "resource_group_name" {
  description = "Name of the created Resource Group"
  value       = azurerm_resource_group.this.name
}

output "location" {
  description = "Azure region of the Resource Group"
  value       = azurerm_resource_group.this.location
}

output "vnet_id" {
  description = "ID of the Virtual Network"
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the Virtual Network"
  value       = azurerm_virtual_network.this.name
}

output "subnet_ids" {
  description = "Map of subnet name to subnet ID"
  value       = { for name, subnet in azurerm_subnet.this : name => subnet.id }
}
