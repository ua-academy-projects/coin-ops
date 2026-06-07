# outputs.tf

output "workspace_id" {
  value = azurerm_log_analytics_workspace.this.id
}

output "workspace_name" {
  value = azurerm_log_analytics_workspace.this.name
}

output "workspace_customer_id" {
  value = azurerm_log_analytics_workspace.this.workspace_id
}
