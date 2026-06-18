output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.dev.id
}

output "log_analytics_workspace_name" {
  value = azurerm_log_analytics_workspace.dev.name
}

output "action_group_id" {
  value = local.alerts_enabled ? azurerm_monitor_action_group.dev[0].id : null
}
