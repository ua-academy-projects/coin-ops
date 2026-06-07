# main.tf

resource "azurerm_log_analytics_workspace" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_virtual_machine_extension" "azure_monitor_agent" {
  for_each = var.vm_ids

  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = each.value
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.41"
  auto_upgrade_minor_version = true
}

resource "azurerm_monitor_data_collection_rule" "vm_metrics" {
  name                = "${var.name}-vm-dcr"
  resource_group_name = var.resource_group_name
  location            = var.location

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.this.id
      name                  = "log-analytics"
    }
  }

  data_sources {
    performance_counter {
      name                          = "linux-performance"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "\\Processor(_Total)\\% Processor Time",
        "\\Memory\\Available MBytes",
        "\\LogicalDisk(*)\\% Free Space",
        "\\Network(*)\\Bytes Total/sec"
      ]
    }

    syslog {
      name           = "linux-syslog"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["auth", "authpriv", "cron", "daemon", "kern", "syslog", "user"]
      log_levels     = ["Warning", "Error", "Critical", "Alert", "Emergency"]
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf", "Microsoft-Syslog"]
    destinations = ["log-analytics"]
  }
}

resource "azurerm_monitor_data_collection_rule_association" "vm_metrics" {
  for_each = var.vm_ids

  name                    = "${each.key}-vm-dcr-association"
  target_resource_id      = each.value
  data_collection_rule_id = azurerm_monitor_data_collection_rule.vm_metrics.id
}

resource "azurerm_monitor_diagnostic_setting" "postgresql" {
  count = var.postgresql_server_id != null ? 1 : 0

  name                       = "${var.name}-postgresql-diagnostic"
  target_resource_id         = var.postgresql_server_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category = "PostgreSQLLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}
