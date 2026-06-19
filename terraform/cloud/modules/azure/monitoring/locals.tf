locals {
  frontend_base_url = var.frontend_public_ip != null ? "http://${var.frontend_public_ip}" : null
  action_group_ids  = var.alert_email != null && var.alert_email != "" ? [azurerm_monitor_action_group.this[0].id] : []

  aks_metric_alerts = var.aks_alerts_enabled && var.aks_monitoring_enabled ? {
    node_cpu_high = {
      name        = "${var.name}-aks-node-cpu-high"
      description = "AKS node CPU usage is higher than 80 percent."
      metric_name = "node_cpu_usage_percentage"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 80
      severity    = 2
      frequency   = "PT5M"
      window_size = "PT15M"
    }
    node_memory_high = {
      name        = "${var.name}-aks-node-memory-high"
      description = "AKS node memory working set is higher than 80 percent."
      metric_name = "node_memory_working_set_percentage"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 80
      severity    = 2
      frequency   = "PT5M"
      window_size = "PT15M"
    }
    node_disk_high = {
      name        = "${var.name}-aks-node-disk-high"
      description = "AKS node disk usage is higher than 80 percent."
      metric_name = "node_disk_usage_percentage"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 80
      severity    = 2
      frequency   = "PT5M"
      window_size = "PT15M"
    }
    unschedulable_pods = {
      name        = "${var.name}-aks-unschedulable-pods"
      description = "AKS has pods that cannot be scheduled."
      metric_name = "cluster_autoscaler_unschedulable_pods_count"
      aggregation = "Average"
      operator    = "GreaterThan"
      threshold   = 0
      severity    = 1
      frequency   = "PT5M"
      window_size = "PT15M"
    }
  } : {}

  availability_tests = var.http_availability_tests_enabled && local.frontend_base_url != null ? {
    frontend = "${local.frontend_base_url}/health"
    proxy    = "${local.frontend_base_url}/api/health"
    history  = "${local.frontend_base_url}/history-api/health"
  } : {}

  workbook_data = {
    version = "Notebook/1.0"
    items = [
      {
        type = 1
        content = {
          json = "# Coin-Ops AKS Monitoring\nAzure-native overview for AKS, PostgreSQL, and app platform signals."
        }
      },
      {
        type = 3
        content = {
          version       = "KqlItem/1.0"
          title         = "AKS node CPU, memory, and disk"
          queryType     = 0
          resourceType  = "microsoft.operationalinsights/workspaces"
          visualization = "timechart"
          size          = 0
          timeContext = {
            durationMs = 3600000
          }
          query = <<-KQL
            AzureMetrics
            | where ResourceProvider == "MICROSOFT.CONTAINERSERVICE"
            | where MetricName in ("node_cpu_usage_percentage", "node_memory_working_set_percentage", "node_disk_usage_percentage")
            | summarize Average = avg(Average) by MetricName, bin(TimeGenerated, 5m)
            | order by TimeGenerated asc
          KQL
        }
      },
      {
        type = 3
        content = {
          version       = "KqlItem/1.0"
          title         = "AKS unschedulable pods"
          queryType     = 0
          resourceType  = "microsoft.operationalinsights/workspaces"
          visualization = "timechart"
          size          = 0
          timeContext = {
            durationMs = 3600000
          }
          query = <<-KQL
            AzureMetrics
            | where ResourceProvider == "MICROSOFT.CONTAINERSERVICE"
            | where MetricName == "cluster_autoscaler_unschedulable_pods_count"
            | summarize UnschedulablePods = avg(Average) by bin(TimeGenerated, 5m)
            | order by TimeGenerated asc
          KQL
        }
      },
      {
        type = 3
        content = {
          version       = "KqlItem/1.0"
          title         = "PostgreSQL CPU, storage, and connections"
          queryType     = 0
          resourceType  = "microsoft.operationalinsights/workspaces"
          visualization = "timechart"
          size          = 0
          timeContext = {
            durationMs = 3600000
          }
          query = <<-KQL
            AzureMetrics
            | where ResourceProvider == "MICROSOFT.DBFORPOSTGRESQL"
            | where MetricName in ("cpu_percent", "storage_percent", "active_connections", "connections_failed")
            | summarize Average = avg(Average) by MetricName, bin(TimeGenerated, 5m)
            | order by TimeGenerated asc
          KQL
        }
      },
      {
        type = 3
        content = {
          version       = "KqlItem/1.0"
          title         = "Recent AKS control-plane logs"
          queryType     = 0
          resourceType  = "microsoft.operationalinsights/workspaces"
          visualization = "table"
          size          = 0
          timeContext = {
            durationMs = 3600000
          }
          query = <<-KQL
            AzureDiagnostics
            | where ResourceProvider == "MICROSOFT.CONTAINERSERVICE"
            | project TimeGenerated, Category, OperationName, log_s
            | order by TimeGenerated desc
            | take 50
          KQL
        }
      }
    ]
    fallbackResourceIds = [
      lower(azurerm_log_analytics_workspace.this.id)
    ]
  }
}
