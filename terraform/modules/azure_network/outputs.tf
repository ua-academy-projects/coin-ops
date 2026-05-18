output "resource_group_name" {
  value = try(data.azurerm_resource_group.main[0].name, null)
}

output "resource_group_location" {
  value = try(data.azurerm_resource_group.main[0].location, null)
}

output "vnet_id" {
  value = try(azurerm_virtual_network.main[0].id, null)
}

output "vnet_name" {
  value = try(azurerm_virtual_network.main[0].name, null)
}

output "public_subnet_id" {
  value = try(azurerm_subnet.public[0].id, null)
}

output "public_subnet_b_id" {
  value = try(azurerm_subnet.public_b[0].id, null)
}

output "private_subnet_id" {
  value = try(azurerm_subnet.private[0].id, null)
}

output "private_subnet_b_id" {
  value = try(azurerm_subnet.private_b[0].id, null)
}