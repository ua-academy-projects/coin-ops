locals {
  native_obs_enabled = (
    local.obs_enabled &&
    try(local.config.observability.azure_native.enabled, false)
  )

  native_metrics_export_enabled = (
    local.native_obs_enabled &&
    try(local.config.observability.azure_native.export_platform_metrics, true)
  )
  native_alerts_enabled = (
    local.native_obs_enabled &&
    try(local.config.observability.azure_native.alerts_enabled, true)
  )
  native_workbook_enabled = (
    local.native_obs_enabled &&
    try(local.config.observability.azure_native.workbook_enabled, true)
  )

  native_cpu_threshold = try(
    local.config.observability.azure_native.cpu_threshold_percent,
    85
  )
  native_nat_packet_drop_threshold = try(
    local.config.observability.azure_native.nat_packet_drop_threshold,
    0
  )

  native_targets = local.is_azure && length(module.azure) > 0 ? module.azure[0].monitoring_targets : {
    virtual_machines = {}
    nat_gateway_id   = ""
    key_vault_id     = ""
  }

  native_all_vm_ids = [
    for target in values(local.native_targets.virtual_machines) : target.id
  ]
  native_k3s_vm_ids = [
    for target in values(local.native_targets.virtual_machines) : target.id
    if target.role == "k3s"
  ]

  native_k3s_vm_id = try(local.native_k3s_vm_ids[0], "")

  native_workbook_queries = {
    telemetry_inventory = <<-KQL
      AzureMetrics
      | where TimeGenerated > ago(1h)
      | summarize Samples=count(), LastSeen=max(TimeGenerated) by ResourceId, MetricName
      | order by ResourceId asc, MetricName asc
    KQL

    k3s_cpu = <<-KQL
      AzureMetrics
      | where ResourceId =~ "${local.native_k3s_vm_id}"
      | where MetricName == "Percentage CPU"
      | summarize CPUPercent=avg(Average) by bin(TimeGenerated, 5m)
      | render timechart
    KQL

    k3s_availability = <<-KQL
      AzureMetrics
      | where ResourceId =~ "${local.native_k3s_vm_id}"
      | where MetricName == "VmAvailabilityMetric"
      | summarize Availability=min(Minimum) by bin(TimeGenerated, 5m)
      | render timechart
    KQL

    k3s_network = <<-KQL
      AzureMetrics
      | where ResourceId =~ "${local.native_k3s_vm_id}"
      | where MetricName in ("Network In Total", "Network Out Total")
      | summarize Bytes=sum(Total) by MetricName, bin(TimeGenerated, 5m)
      | render timechart
    KQL

    key_vault_audit = <<-KQL
      AzureDiagnostics
      | where TimeGenerated > ago(24h)
      | where ResourceProvider == "MICROSOFT.KEYVAULT"
      | summarize Requests=count() by ResultType, bin(TimeGenerated, 15m)
      | render timechart
    KQL
  }
}

resource "azurerm_monitor_diagnostic_setting" "native_vm" {
  for_each = local.native_metrics_export_enabled ? local.native_targets.virtual_machines : {}

  name                       = "${local.config.name_prefix}-native-${each.value.role}"
  target_resource_id         = each.value.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.obs[0].id

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "native_nat_gateway" {
  count = local.native_metrics_export_enabled ? 1 : 0

  name                       = "${local.config.name_prefix}-native-nat"
  target_resource_id         = local.native_targets.nat_gateway_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.obs[0].id

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "native_key_vault" {
  count = local.native_metrics_export_enabled ? 1 : 0

  name                       = "${local.config.name_prefix}-native-keyvault"
  target_resource_id         = local.native_targets.key_vault_id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.obs[0].id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_metric_alert" "native_vm_unavailable" {
  count = local.native_alerts_enabled ? 1 : 0

  name                     = "${local.config.name_prefix}-native-vm-unavailable"
  resource_group_name      = local.obs_rg
  scopes                   = local.native_all_vm_ids
  target_resource_type     = "Microsoft.Compute/virtualMachines"
  target_resource_location = local.obs_loc
  description              = "A CoinOps Azure VM availability metric fell below 1."
  severity                 = 1
  frequency                = "PT1M"
  window_size              = "PT5M"
  auto_mitigate            = true

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "VmAvailabilityMetric"
    aggregation      = "Minimum"
    operator         = "LessThan"
    threshold        = 1
  }

  action {
    action_group_id = azurerm_monitor_action_group.obs[0].id
  }
}

resource "azurerm_monitor_metric_alert" "native_k3s_high_cpu" {
  count = local.native_alerts_enabled && length(local.native_k3s_vm_ids) > 0 ? 1 : 0

  name                     = "${local.config.name_prefix}-native-k3s-high-cpu"
  resource_group_name      = local.obs_rg
  scopes                   = local.native_k3s_vm_ids
  target_resource_type     = "Microsoft.Compute/virtualMachines"
  target_resource_location = local.obs_loc
  description              = "Average k3s VM CPU exceeded the configured threshold for 15 minutes."
  severity                 = 2
  frequency                = "PT5M"
  window_size              = "PT15M"
  auto_mitigate            = true

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = local.native_cpu_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.obs[0].id
  }
}

resource "azurerm_monitor_metric_alert" "native_nat_packet_drops" {
  count = local.native_alerts_enabled ? 1 : 0

  name                = "${local.config.name_prefix}-native-nat-packet-drops"
  resource_group_name = local.obs_rg
  scopes              = [local.native_targets.nat_gateway_id]
  description         = "The CoinOps NAT Gateway dropped packets during the last five minutes."
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  auto_mitigate       = true

  criteria {
    metric_namespace = "Microsoft.Network/natGateways"
    metric_name      = "PacketDropCount"
    aggregation      = "Total"
    operator         = "GreaterThan"
    threshold        = local.native_nat_packet_drop_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.obs[0].id
  }
}

resource "azurerm_application_insights_workbook" "native" {
  count = local.native_workbook_enabled ? 1 : 0

  name = uuidv5(
    "url",
    lower("https://coinops.local/${local.config.clouds.azure.subscription_id}/${local.obs_rg}/azure-native-monitoring")
  )
  resource_group_name = local.obs_rg
  location            = local.obs_loc
  display_name        = "CoinOps Azure Native Monitoring"
  source_id           = lower(azurerm_log_analytics_workspace.obs[0].id)
  category            = "workbook"
  description         = "Azure platform metrics, resource diagnostics, and native alerts for the CoinOps k3s lab."

  data_json = jsonencode({
    version = "Notebook/1.0"
    items = concat(
      [
        {
          type = 1
          name = "overview"
          content = {
            json = "# CoinOps Azure Native Monitoring\nPlatform telemetry from Azure resources. Existing Prometheus, Grafana, Arc, Beyla, OTel, and exporter monitoring remains separate and unchanged."
          }
        }
      ],
      [
        for key, query in local.native_workbook_queries : {
          type = 3
          name = key
          content = {
            version      = "KqlItem/1.0"
            query        = query
            size         = 0
            title        = title(replace(key, "_", " "))
            timeContext  = { durationMs = 3600000 }
            queryType    = 0
            resourceType = "microsoft.operationalinsights/workspaces"
          }
        }
      ],
      [
        {
          type = 10
          name = "nat_gateway_traffic"
          content = {
            chartId      = "workbook${uuidv5("url", "${local.native_targets.nat_gateway_id}/traffic")}"
            version      = "MetricsItem/2.0"
            size         = 0
            chartType    = 2
            resourceType = "microsoft.network/natgateways"
            metricScope  = 0
            resourceIds  = [local.native_targets.nat_gateway_id]
            timeContext  = { durationMs = 3600000 }
            metrics = [
              {
                namespace   = "microsoft.network/natgateways"
                metric      = "microsoft.network/natgateways--ByteCount"
                aggregation = 1
                columnName  = "Bytes"
              },
              {
                namespace   = "microsoft.network/natgateways"
                metric      = "microsoft.network/natgateways--PacketCount"
                aggregation = 1
                columnName  = "Packets"
              },
              {
                namespace   = "microsoft.network/natgateways"
                metric      = "microsoft.network/natgateways--SNATConnectionCount"
                aggregation = 1
                columnName  = "SNAT Connections"
              }
            ]
            title               = "NAT Gateway Traffic"
            showOpenInMe        = true
            showCreateAlertRule = true
            gridSettings        = { rowLimit = 10000 }
          }
          styleSettings = { showBorder = true }
        },
        {
          type = 10
          name = "nat_gateway_health"
          content = {
            chartId      = "workbook${uuidv5("url", "${local.native_targets.nat_gateway_id}/health")}"
            version      = "MetricsItem/2.0"
            size         = 0
            chartType    = 2
            resourceType = "microsoft.network/natgateways"
            metricScope  = 0
            resourceIds  = [local.native_targets.nat_gateway_id]
            timeContext  = { durationMs = 3600000 }
            metrics = [
              {
                namespace   = "microsoft.network/natgateways"
                metric      = "microsoft.network/natgateways--DatapathAvailability"
                aggregation = 4
                columnName  = "Datapath Availability"
              },
              {
                namespace   = "microsoft.network/natgateways"
                metric      = "microsoft.network/natgateways--PacketDropCount"
                aggregation = 1
                columnName  = "Dropped Packets"
              }
            ]
            title               = "NAT Gateway Health"
            showOpenInMe        = true
            showCreateAlertRule = true
            gridSettings        = { rowLimit = 10000 }
          }
          styleSettings = { showBorder = true }
        }
      ]
    )
    isLocked            = false
    fallbackResourceIds = [azurerm_log_analytics_workspace.obs[0].id]
  })

  tags = {
    project = local.config.name_prefix
    layer   = "azure-native-monitoring"
  }
}

output "azure_native_monitoring" {
  value = local.native_obs_enabled ? {
    workbook_id   = try(azurerm_application_insights_workbook.native[0].id, null)
    workbook_name = try(azurerm_application_insights_workbook.native[0].display_name, null)
    workspace_id  = azurerm_log_analytics_workspace.obs[0].id
    alert_names = [
      try(azurerm_monitor_metric_alert.native_vm_unavailable[0].name, null),
      try(azurerm_monitor_metric_alert.native_k3s_high_cpu[0].name, null),
      try(azurerm_monitor_metric_alert.native_nat_packet_drops[0].name, null)
    ]
  } : null
}
