resource "azurerm_resource_group" "dev" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

moved {
  from = azurerm_resource_group.this
  to   = azurerm_resource_group.dev
}
