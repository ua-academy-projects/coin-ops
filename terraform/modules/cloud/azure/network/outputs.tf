output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "network_id" {
  value = azurerm_virtual_network.this.id

  depends_on = [time_sleep.after_subnets]
}

output "subnet_ids" {
  value = { for name, subnet in azurerm_subnet.this : name => subnet.id }

  depends_on = [time_sleep.after_subnets]
}

output "private_subnet_ids" {
  value = { for name in keys(local.private_subnets) : name => azurerm_subnet.this[name].id }

  depends_on = [time_sleep.after_subnets]
}

output "database_subnet_id" {
  value = try(azurerm_subnet.this["database"].id, "")

  depends_on = [time_sleep.after_subnets]
}
