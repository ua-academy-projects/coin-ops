# main.tf
#TODO: optimize code (merge repited resources)

resource "azurerm_log_analytics_workspace" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_monitor_action_group" "this" {
  count = var.alert_email != null && var.alert_email != "" ? 1 : 0

  name                = "${var.name}-alerts"
  resource_group_name = var.resource_group_name
  short_name          = "coinopsmon"

  email_receiver {
    name                    = "primary"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
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
  count = var.postgresql_monitoring_enabled ? 1 : 0

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

resource "azurerm_monitor_diagnostic_setting" "aks" {
  count = var.aks_monitoring_enabled ? 1 : 0

  name                       = "${var.name}-aks-diagnostic"
  target_resource_id         = var.aks_cluster_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  dynamic "enabled_log" {
    for_each = toset(var.aks_log_categories)

    content {
      category = enabled_log.value
    }
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_metric_alert" "vm_cpu_high" {
  for_each = var.vm_cpu_alert_enabled ? var.vm_ids : {}

  name                = "${each.key}-cpu-high"
  resource_group_name = var.resource_group_name
  scopes              = [each.value]
  description         = "VM CPU usage is higher than 80 percent."
  severity            = 2      # Warning
  frequency           = "PT1M" # Period Time 1 Minute
  window_size         = "PT5M"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  dynamic "action" {
    for_each = local.action_group_ids

    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "aks" {
  for_each = local.aks_metric_alerts

  name                = each.value.name
  resource_group_name = var.resource_group_name
  scopes              = [var.aks_cluster_id]
  description         = each.value.description
  severity            = each.value.severity
  frequency           = each.value.frequency
  window_size         = each.value.window_size
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.ContainerService/managedClusters"
    metric_name      = each.value.metric_name
    aggregation      = each.value.aggregation
    operator         = each.value.operator
    threshold        = each.value.threshold
  }

  dynamic "action" {
    for_each = local.action_group_ids

    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "postgresql_cpu_high" {
  count = var.postgresql_cpu_alert_enabled && var.postgresql_monitoring_enabled ? 1 : 0

  name                = "${var.name}-postgresql-cpu-high"
  resource_group_name = var.resource_group_name
  scopes              = [var.postgresql_server_id]
  description         = "PostgreSQL CPU usage is higher than 80 percent."
  severity            = 2      # Warning
  frequency           = "PT1M" # Period Time 1 Minute
  window_size         = "PT5M"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "cpu_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  dynamic "action" {
    for_each = local.action_group_ids

    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "postgresql_storage_high" {
  count = var.postgresql_storage_alert_enabled && var.postgresql_monitoring_enabled ? 1 : 0

  name                = "${var.name}-postgresql-storage-high"
  resource_group_name = var.resource_group_name
  scopes              = [var.postgresql_server_id]
  description         = "PostgreSQL storage usage is higher than 80 percent."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "storage_percent"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  dynamic "action" {
    for_each = local.action_group_ids

    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "postgresql_connections_high" {
  count = var.postgresql_connections_alert_enabled && var.postgresql_monitoring_enabled ? 1 : 0

  name                = "${var.name}-postgresql-connections-high"
  resource_group_name = var.resource_group_name
  scopes              = [var.postgresql_server_id]
  description         = "PostgreSQL active connections are high."
  severity            = 3
  frequency           = "PT5M"
  window_size         = "PT15M"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "active_connections"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  dynamic "action" {
    for_each = local.action_group_ids

    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_monitor_metric_alert" "postgresql_failed_connections" {
  count = var.postgresql_failed_connections_alert_enabled && var.postgresql_monitoring_enabled ? 1 : 0

  name                = "${var.name}-postgresql-failed-connections"
  resource_group_name = var.resource_group_name
  scopes              = [var.postgresql_server_id]
  description         = "PostgreSQL has failed connections."
  severity            = 2
  frequency           = "PT5M"
  window_size         = "PT15M"
  enabled             = true

  criteria {
    metric_namespace = "Microsoft.DBforPostgreSQL/flexibleServers"
    metric_name      = "connections_failed"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = 0
  }

  dynamic "action" {
    for_each = local.action_group_ids

    content {
      action_group_id = action.value
    }
  }
}

resource "azurerm_application_insights_workbook" "this" {
  count = var.workbook_enabled && var.aks_monitoring_enabled ? 1 : 0

  name                = var.workbook_name
  resource_group_name = var.resource_group_name
  location            = var.location
  display_name        = "Coin-Ops AKS Monitoring"
  description         = "Azure-native dashboard for Coin-Ops AKS, PostgreSQL, and control-plane logs."
  category            = "workbook"
  source_id           = lower(azurerm_log_analytics_workspace.this.id)
  data_json           = jsonencode(local.workbook_data)
}

# -> commented because consumes a lot
# resource "azurerm_application_insights" "this" {
#   count = var.http_availability_tests_enabled ? 1 : 0
#
#   name                = "${var.name}-appinsights"
#   location            = var.location
#   resource_group_name = var.resource_group_name
#   workspace_id        = azurerm_log_analytics_workspace.this.id
#   application_type    = "web"
# }
#
# resource "azurerm_application_insights_standard_web_test" "availability" {
#   for_each = local.availability_tests
#
#   name                    = "${var.name}-${each.key}-availability"
#   resource_group_name     = var.resource_group_name
#   location                = var.location
#   application_insights_id = azurerm_application_insights.this[0].id
#   geo_locations           = ["emea-nl-ams-azr"]
#   frequency               = 300
#   timeout                 = 30
#   enabled                 = true
#
#   request {
#     url       = each.value
#     http_verb = "GET"
#   }
#
#   validation_rules {
#     expected_status_code        = 200
#   }
# }
