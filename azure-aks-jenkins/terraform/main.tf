data "azurerm_client_config" "current" {}

module "resource_group" {
  source              = "../modules/resource-group"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

module "network" {
  source              = "../modules/network"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  vnet_name           = "${var.name_prefix}-${var.environment}-vnet"
  vnet_cidr           = var.vnet_cidr
  aks_subnet_cidr     = var.aks_subnet_cidr
  app_subnet_cidr     = var.app_subnet_cidr
  tags                = var.tags
}

module "acr" {
  source              = "../modules/acr"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  acr_name            = var.acr_name
  tags                = var.tags
}

module "monitoring" {
  source                         = "../modules/monitoring"
  resource_group_name            = module.resource_group.name
  resource_group_id              = module.resource_group.id
  location                       = module.resource_group.location
  cluster_name                   = var.aks_name
  app_namespace                  = var.app_namespace
  workspace_name                 = var.monitoring_workspace_name
  action_group_name              = var.monitoring_action_group_name
  action_group_short_name        = var.monitoring_action_group_short_name
  alert_email                    = var.alert_email
  log_retention_days             = var.log_retention_days
  cpu_alert_threshold            = var.cpu_alert_threshold
  cpu_alert_severity             = var.cpu_alert_severity
  heartbeat_alert_severity       = var.heartbeat_alert_severity
  heartbeat_window_minutes       = var.heartbeat_window_minutes
  heartbeat_evaluation_frequency = var.heartbeat_evaluation_frequency
  tags                           = var.tags
}

module "aks" {
  source                     = "../modules/aks"
  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  cluster_name               = var.aks_name
  dns_prefix                 = var.dns_prefix
  kubernetes_version         = var.kubernetes_version
  node_count                 = var.node_count
  node_vm_size               = var.node_vm_size
  subnet_id                  = module.network.aks_subnet_id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  tags                       = var.tags
}

module "rbac" {
  source            = "../modules/rbac"
  acr_id            = module.acr.id
  kubelet_object_id = module.aks.kubelet_object_id
}

module "traefik" {
  source             = "../modules/traefik"
  namespace          = var.ingress_controller_namespace
  release_name       = var.ingress_controller_release_name
  chart_version      = var.ingress_controller_chart_version
  ingress_class_name = var.ingress_class_name
  depends_on         = [module.aks]
}

module "cert_manager" {
  source              = "../modules/cert-manager"
  namespace           = var.cert_manager_namespace
  release_name        = var.cert_manager_release_name
  chart_version       = var.cert_manager_chart_version
  cluster_issuer_name = var.cluster_issuer_name
  letsencrypt_email   = var.letsencrypt_email
  ingress_class_name  = var.ingress_class_name
  depends_on          = [module.traefik]
}

module "jenkins" {
  source                         = "../modules/jenkins"
  resource_group_name            = module.resource_group.name
  location                       = module.resource_group.location
  jenkins_namespace              = var.jenkins_namespace
  app_namespace                  = var.app_namespace
  jenkins_admin_username         = var.jenkins_admin_username
  jenkins_admin_password         = var.jenkins_admin_password
  jenkins_storage_size           = var.jenkins_storage_size
  jenkins_chart_version          = var.jenkins_chart_version
  acr_login_server               = module.acr.login_server
  acr_username                   = module.acr.admin_username
  acr_password                   = module.acr.admin_password
  azure_subscription_id          = data.azurerm_client_config.current.subscription_id
  azure_tenant_id                = data.azurerm_client_config.current.tenant_id
  jenkins_values_template_path   = "${path.root}/../helm/jenkins/values.yaml.tpl"
  depends_on_aks_ready_indicator = module.aks.id
  depends_on                     = [module.traefik, module.cert_manager]
}

module "monitoring_identity" {
  source                     = "../modules/monitoring-identity"
  resource_group_name        = module.resource_group.name
  location                   = module.resource_group.location
  identity_name              = var.monitoring_identity_name
  resource_group_scope       = module.resource_group.id
  log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
  tags                       = var.tags
}
