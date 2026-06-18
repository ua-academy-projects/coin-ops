locals {
  alerts_enabled = var.alert_email != null && trimspace(var.alert_email) != ""
}

resource "azurerm_log_analytics_workspace" "dev" {
  name                = var.workspace_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

resource "azurerm_monitor_action_group" "dev" {
  count               = local.alerts_enabled ? 1 : 0
  name                = var.action_group_name
  resource_group_name = var.resource_group_name
  short_name          = var.action_group_short_name
  tags                = var.tags

  email_receiver {
    name                    = "primary-email"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "node_not_ready" {
  count                            = local.alerts_enabled ? 1 : 0
  name                             = "${var.cluster_name}-node-not-ready"
  resource_group_name              = var.resource_group_name
  location                         = var.location
  display_name                     = "${var.cluster_name} node not ready"
  description                      = "Fire when one or more AKS nodes are not Ready."
  severity                         = 2
  enabled                          = true
  evaluation_frequency             = "PT5M"
  window_duration                  = "PT10M"
  scopes                           = [azurerm_log_analytics_workspace.dev.id]
  auto_mitigation_enabled          = true
  workspace_alerts_storage_enabled = false
  tags                             = var.tags

  criteria {
    query                   = <<-KQL
      KubeNodeInventory
      | where ClusterName =~ "${var.cluster_name}"
      | where TimeGenerated > ago(10m)
      | summarize LastStatus = arg_max(TimeGenerated, Status) by Computer
      | where LastStatus != "Ready"
    KQL
    operator                = "GreaterThan"
    threshold               = 0
    time_aggregation_method = "Count"

    failing_periods {
      number_of_evaluation_periods             = 1
      minimum_failing_periods_to_trigger_alert = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.dev[0].id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "pods_not_running" {
  count                            = local.alerts_enabled ? 1 : 0
  name                             = "${var.cluster_name}-pods-not-running"
  resource_group_name              = var.resource_group_name
  location                         = var.location
  display_name                     = "${var.cluster_name} application pods not running"
  description                      = "Fire when application pods are Pending, Failed, or Unknown."
  severity                         = 2
  enabled                          = true
  evaluation_frequency             = "PT5M"
  window_duration                  = "PT10M"
  scopes                           = [azurerm_log_analytics_workspace.dev.id]
  auto_mitigation_enabled          = true
  workspace_alerts_storage_enabled = false
  tags                             = var.tags

  criteria {
    query                   = <<-KQL
      KubePodInventory
      | where ClusterName =~ "${var.cluster_name}"
      | where Namespace == "${var.app_namespace}"
      | where TimeGenerated > ago(10m)
      | summarize LastStatus = arg_max(TimeGenerated, PodStatus) by Name
      | where LastStatus in ("Pending", "Failed", "Unknown")
    KQL
    operator                = "GreaterThan"
    threshold               = 0
    time_aggregation_method = "Count"

    failing_periods {
      number_of_evaluation_periods             = 1
      minimum_failing_periods_to_trigger_alert = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.dev[0].id]
  }
}

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "pod_restarts_high" {
  count                            = local.alerts_enabled ? 1 : 0
  name                             = "${var.cluster_name}-pod-restarts-high"
  resource_group_name              = var.resource_group_name
  location                         = var.location
  display_name                     = "${var.cluster_name} pod restarts high"
  description                      = "Fire when pods in the application namespace restart repeatedly."
  severity                         = 3
  enabled                          = true
  evaluation_frequency             = "PT5M"
  window_duration                  = "PT15M"
  scopes                           = [azurerm_log_analytics_workspace.dev.id]
  auto_mitigation_enabled          = true
  workspace_alerts_storage_enabled = false
  tags                             = var.tags

  criteria {
    query                   = <<-KQL
      KubePodInventory
      | where ClusterName =~ "${var.cluster_name}"
      | where Namespace == "${var.app_namespace}"
      | where TimeGenerated > ago(15m)
      | summarize RestartCount = max(ContainerRestartCount) by Name, ContainerName
      | where RestartCount >= 3
    KQL
    operator                = "GreaterThan"
    threshold               = 0
    time_aggregation_method = "Count"

    failing_periods {
      number_of_evaluation_periods             = 1
      minimum_failing_periods_to_trigger_alert = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.dev[0].id]
  }
}
