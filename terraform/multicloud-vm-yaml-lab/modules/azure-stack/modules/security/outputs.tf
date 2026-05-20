output "security_group_ids" {
  value = {
    bastion  = azurerm_network_security_group.bastion.id
    app      = azurerm_network_security_group.app.id
    database = azurerm_network_security_group.database.id
  }
}
