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

module "aks" {
  source              = "../modules/aks"
  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  cluster_name        = var.aks_name
  dns_prefix          = var.dns_prefix
  kubernetes_version  = var.kubernetes_version
  node_count          = var.node_count
  node_vm_size        = var.node_vm_size
  subnet_id           = module.network.aks_subnet_id
  tags                = var.tags
}

module "rbac" {
  source            = "../modules/rbac"
  acr_id            = module.acr.id
  kubelet_object_id = module.aks.kubelet_object_id
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
}
