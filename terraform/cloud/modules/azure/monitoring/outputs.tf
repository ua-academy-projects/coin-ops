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

output "application_insights_id" {
  value = try(azurerm_application_insights.this[0].id, null)
}

output "vm_cpu_alert_names" {
  value = {
    for key, alert in azurerm_monitor_metric_alert.vm_cpu_high : key => alert.name
  }
}

output "postgresql_alert_names" {
  value = {
    cpu                = try(azurerm_monitor_metric_alert.postgresql_cpu_high[0].name, null)
    storage            = try(azurerm_monitor_metric_alert.postgresql_storage_high[0].name, null)
    connections        = try(azurerm_monitor_metric_alert.postgresql_connections_high[0].name, null)
    failed_connections = try(azurerm_monitor_metric_alert.postgresql_failed_connections[0].name, null)
  }
}

output "availability_test_names" {
  value = {
    for key, test in azurerm_application_insights_standard_web_test.availability : key => test.name
  }
}
