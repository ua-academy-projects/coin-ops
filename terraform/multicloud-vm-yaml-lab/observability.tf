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
  obs_email = try(local.config.observability.alert_email, "andriy@netlife.com.ua")
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
  grafana_major_version             = 10
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
    action_group_id              = azurerm_monitor_action_group.obs[0].id
  } : null
  sensitive = true
}
