output "vnet_id" {
  value = azurerm_virtual_network.dev.id
}

output "aks_subnet_id" {
  value = azurerm_subnet.aks.id
}

output "app_subnet_id" {
  value = azurerm_subnet.app.id
}
