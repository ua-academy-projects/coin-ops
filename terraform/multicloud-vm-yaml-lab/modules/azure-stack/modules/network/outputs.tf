output "resource_group_name" {
  value = data.azurerm_resource_group.this.name
}

output "location" {
  value = data.azurerm_resource_group.this.location
}

output "network_name" {
  value = azurerm_virtual_network.this.name
}

output "network_id" {
  value = azurerm_virtual_network.this.id
}

output "public_subnet_ids" {
  value = { for key, subnet in azurerm_subnet.public : key => subnet.id }
}

output "private_subnet_ids" {
  value = { for key, subnet in azurerm_subnet.private : key => subnet.id }
}

output "database_subnet_id" {
  value = azurerm_subnet.database.id
}

output "app_gateway_subnet_id" {
  value = azurerm_subnet.app_gateway.id
}

output "nat_gateway_id" {
  value = azurerm_nat_gateway.this.id
}
