resource "azurerm_user_assigned_identity" "this" {
  name                = var.identity_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "monitoring_reader_rg" {
  scope                = var.resource_group_scope
  role_definition_name = "Monitoring Reader"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_role_assignment" "reader_rg" {
  scope                = var.resource_group_scope
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azurerm_role_assignment" "log_analytics_reader" {
  scope                = var.log_analytics_workspace_id
  role_definition_name = "Log Analytics Reader"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}
