# Azure Monitor observability backend (DRAFT — unverified until applied on WSL).
#
# The data-plane Azure resources for the full cycle: logs (Log Analytics),
# metrics (Azure Monitor Workspace / managed Prometheus), traces (Application
# Insights), dashboards (Azure Managed Grafana), and the alert action group.
# The IN-CLUSTER pieces — Arc connect, the Container Insights + Managed
# Prometheus extensions, Beyla, the OTel collector — live in the ansible role
# `k3s_observability` (mirrors the manual pilot guide, docs/observability/).
#
# Gated OFF by default (observability.enabled in config/lab.yaml). Flip it on
# AFTER the cluster is up and Arc-connected, so it never affects the Phase-0
# provisioning apply. No-op on AWS/GCP and on the cloud-native (non-k3s) path.

locals {
  obs_enabled = local.is_azure && length(local.k3s_names) > 0 && try(local.config.observability.enabled, false)
  # Resolve to the real RG when on Azure (gives the dependency on module.azure)
  # and to a non-blank placeholder otherwise — azurerm validates resource_group_name
  # as non-empty even for count=0 resources, so it must never be "".
  obs_rg    = local.is_azure ? module.azure[0].resource_group_name : "n-a"
  obs_loc   = local.azure_region
  obs_email = try(local.config.observability.alert_email, "vshabat64@gmail.com")
}

# --- Logs ---------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "obs" {
  count               = local.obs_enabled ? 1 : 0
  name                = "${local.config.name_prefix}-logs"
  resource_group_name = local.obs_rg
  location            = local.obs_loc
  sku                 = "PerGB2018"
  retention_in_days   = 30 # keep low on a student sub; 30 is the interactive floor
}

# --- Metrics (Azure Monitor managed service for Prometheus) -------------------
resource "azurerm_monitor_workspace" "obs" {
  count               = local.obs_enabled ? 1 : 0
  name                = "${local.config.name_prefix}-prom"
  resource_group_name = local.obs_rg
  location            = local.obs_loc
}

# --- Traces (Application Insights, workspace-based) ---------------------------
resource "azurerm_application_insights" "obs" {
  count               = local.obs_enabled ? 1 : 0
  name                = "${local.config.name_prefix}-appins"
  resource_group_name = local.obs_rg
  location            = local.obs_loc
  application_type    = "web"
  workspace_id        = azurerm_log_analytics_workspace.obs[0].id
  sampling_percentage = 20 # bound ingest on a student sub
}

# --- Dashboards (Azure Managed Grafana) --------------------------------------
resource "azurerm_dashboard_grafana" "obs" {
  count                             = local.obs_enabled ? 1 : 0
  name                              = substr("${replace(local.config.name_prefix, "-", "")}graf", 0, 23)
  resource_group_name               = local.obs_rg
  location                          = local.obs_loc
  grafana_major_version             = "12"
  api_key_enabled                   = false
  deterministic_outbound_ip_enabled = false
  public_network_access_enabled     = true

  identity {
    type = "SystemAssigned"
  }

  azure_monitor_workspace_integrations {
    resource_id = azurerm_monitor_workspace.obs[0].id
  }
}

# Grafana's managed identity must be able to query the Monitor Workspace metrics.
resource "azurerm_role_assignment" "grafana_prometheus_reader" {
  count                = local.obs_enabled ? 1 : 0
  scope                = azurerm_monitor_workspace.obs[0].id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = azurerm_dashboard_grafana.obs[0].identity[0].principal_id
}

# The operator(s) need a Grafana RBAC role to open the Managed Grafana UI
# (being subscription Owner is not enough — Grafana access is its own role).
resource "azurerm_role_assignment" "grafana_admin_operators" {
  for_each             = local.obs_enabled ? toset(try(local.config.clouds.azure.operator_object_ids, [])) : toset([])
  scope                = azurerm_dashboard_grafana.obs[0].id
  role_definition_name = "Grafana Admin"
  principal_id         = each.value
}

# --- Alerting (action group = where alerts page) ------------------------------
resource "azurerm_monitor_action_group" "obs" {
  count               = local.obs_enabled ? 1 : 0
  name                = "${local.config.name_prefix}-oncall"
  resource_group_name = local.obs_rg
  short_name          = "coinops"

  email_receiver {
    name          = "ops"
    email_address = local.obs_email
  }
}

# Prometheus alert rules (evaluated against the Azure Monitor Workspace / managed
# Prometheus) → the action group. Infra-level for now (metrics already collected);
# app-level rules (write-path stall, staleness, DLQ) come once the app/backing
# exporters are scraped (pillar D).
resource "azurerm_monitor_alert_prometheus_rule_group" "obs" {
  count               = local.obs_enabled ? 1 : 0
  name                = "${local.config.name_prefix}-k8s-alerts"
  location            = local.obs_loc
  resource_group_name = local.obs_rg
  cluster_name        = "coinops-k3s"
  scopes              = [azurerm_monitor_workspace.obs[0].id]
  rule_group_enabled  = true

  rule {
    alert      = "NodeMemoryPressure"
    expression = "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) > 0.9"
    for        = "PT10M"
    severity   = 2
    labels     = { severity = "warning" }
    annotations = {
      description = "Node {{ $labels.instance }} has <10% memory available for 10m (4 GB nodes — watch it)."
    }
    action {
      action_group_id = azurerm_monitor_action_group.obs[0].id
    }
  }

  rule {
    alert      = "PodRestarting"
    expression = "increase(kube_pod_container_status_restarts_total{namespace=~\"coinops.*\"}[15m]) > 2"
    for        = "PT5M"
    severity   = 3
    labels     = { severity = "warning" }
    annotations = {
      description = "Pod {{ $labels.namespace }}/{{ $labels.pod }} restarted >2 times in 15m."
    }
    action {
      action_group_id = azurerm_monitor_action_group.obs[0].id
    }
  }

  rule {
    alert      = "PodOOMKilled"
    expression = "kube_pod_container_status_last_terminated_reason{reason=\"OOMKilled\", namespace=~\"coinops.*\"} == 1"
    for        = "PT1M"
    severity   = 2
    labels     = { severity = "warning" }
    annotations = {
      description = "Container {{ $labels.namespace }}/{{ $labels.pod }} was OOMKilled."
    }
    action {
      action_group_id = azurerm_monitor_action_group.obs[0].id
    }
  }

  # App-level: the headline write-path-stall demo. Fed by the RabbitMQ prometheus
  # plugin (enabled + scraped by the k3s_observability role). Fires when a queue
  # backs up with no consumers — e.g. scale history-consumer to 0 while the proxy
  # keeps publishing. NOTE: the metric names depend on the RabbitMQ prometheus
  # plugin's output; confirm against the live :15692 /metrics and adjust if your
  # version differs (per-object metrics may need the detailed endpoint).
  rule {
    alert      = "WritePathStall"
    expression = "(sum(rabbitmq_queue_messages_ready) > 100) and (sum(rabbitmq_queue_consumers) == 0)"
    for        = "PT5M"
    severity   = 1
    labels     = { severity = "critical" }
    annotations = {
      description = "RabbitMQ has >100 ready messages and zero consumers for 5m — the history-consumer write path has stalled."
    }
    action {
      action_group_id = azurerm_monitor_action_group.obs[0].id
    }
  }
}

# Consumed by the k3s_observability ansible role (workspace ids, App Insights
# connection string, the Managed Prometheus remote-write/query endpoints).
output "observability" {
  value = local.obs_enabled ? {
    log_analytics_workspace_id   = azurerm_log_analytics_workspace.obs[0].id
    monitor_workspace_id         = azurerm_monitor_workspace.obs[0].id
    prometheus_query_endpoint    = azurerm_monitor_workspace.obs[0].query_endpoint
    app_insights_connection      = azurerm_application_insights.obs[0].connection_string
    app_insights_instrumentation = azurerm_application_insights.obs[0].instrumentation_key
    grafana_endpoint             = azurerm_dashboard_grafana.obs[0].endpoint
    grafana_resource_id          = azurerm_dashboard_grafana.obs[0].id
    action_group_id              = azurerm_monitor_action_group.obs[0].id
  } : null
  sensitive = true
}
