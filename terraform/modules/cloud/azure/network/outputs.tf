output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "network_id" {
  value = azurerm_virtual_network.this.id
}

output "subnet_ids" {
  value = { for name, subnet in azurerm_subnet.this : name => subnet.id }
}

output "private_subnet_ids" {
  value = { for name in keys(local.private_subnets) : name => azurerm_subnet.this[name].id }
}

output "database_subnet_id" {
  value = try(azurerm_subnet.this["database"].id, "")
}
