data "azurerm_client_config" "current" {}

locals {
  stack          = var.stack
  domain_enabled = try(local.stack.domain.enabled, false)
  cloud_native   = try(local.stack.runtime.mode, "external") == "cloud_native"
  api_domain     = try(local.stack.api.domain, local.stack.domain.name)

  safe_prefix   = lower(substr(replace(local.stack.name_prefix, "/[^0-9A-Za-z-]/", ""), 0, 28))
  unique_suffix = substr(sha1("${data.azurerm_client_config.current.subscription_id}-${local.stack.name_prefix}"), 0, 8)

  resource_group_name = try(local.stack.azure.resource_group_name, "") != "" ? local.stack.azure.resource_group_name : "${local.stack.name_prefix}-rg"
  key_vault_name      = try(local.stack.azure.key_vault_name, "") != "" ? local.stack.azure.key_vault_name : substr("${local.safe_prefix}kv${local.unique_suffix}", 0, 24)

  compute_instances = {
    for name, instance in local.stack.instances : name => instance
    if name != local.stack.db_name
  }

  runtime = merge(local.stack.runtime, {
    azure_resource_group  = module.network.resource_group_name
    azure_key_vault_name  = module.secrets.key_vault_name
    azure_subscription_id = data.azurerm_client_config.current.subscription_id
    database              = merge(local.stack.runtime.database, module.database.database)
    queue                 = merge(local.stack.runtime.queue, module.queue.queue)
    cache                 = merge(local.stack.runtime.cache, module.cache.cache)
  })

  app_domain = local.domain_enabled && local.api_domain != "" ? local.api_domain : module.load_balancer.public_ip_address
  app_url    = local.domain_enabled && local.api_domain != "" ? "https://${local.api_domain}" : "http://${module.load_balancer.public_ip_address}"
}

module "network" {
  source = "./modules/network"

  name_prefix         = local.stack.name_prefix
  region              = local.stack.azure.region
  resource_group_name = local.resource_group_name
  network             = local.stack.network
}

module "security" {
  source = "./modules/security"

  name_prefix         = local.stack.name_prefix
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
  firewall            = local.stack.firewall
  app_port            = local.stack.app.port
  public_subnet_ids   = module.network.public_subnet_ids
  private_subnet_ids  = module.network.private_subnet_ids
  database_subnet_id  = module.network.database_subnet_id
}

module "compute" {
  source = "./modules/compute"

  name_prefix         = local.stack.name_prefix
  instances           = local.compute_instances
  ssh                 = local.stack.ssh
  ssh_public_key      = local.stack.ssh_public_key
  app_names           = local.stack.app_names
  bastion_name        = local.stack.bastion_name
  public_subnet_ids   = module.network.public_subnet_ids
  private_subnet_ids  = module.network.private_subnet_ids
  security_groups     = module.security.security_group_ids
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
}

module "load_balancer" {
  source = "./modules/load-balancer"

  depends_on = [module.secrets]

  name_prefix                         = local.stack.name_prefix
  resource_group_name                 = module.network.resource_group_name
  location                            = module.network.location
  app_instances                       = module.compute.app_instances
  gateway_subnet_id                   = module.network.app_gateway_subnet_id
  app_port                            = local.stack.app.port
  health_path                         = local.stack.app.health_path
  api_domain                          = local.api_domain
  gateway_identity_id                 = module.secrets.app_gateway_identity_id
  ssl_certificate_key_vault_secret_id = module.secrets.api_certificate_secret_id
}

module "database" {
  source = "./modules/database"

  name_prefix         = local.stack.name_prefix
  safe_prefix         = local.safe_prefix
  unique_suffix       = local.unique_suffix
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
  network_id          = module.network.network_id
  database_subnet_id  = module.network.database_subnet_id
  runtime             = local.stack.runtime
  db_password         = var.db_password
  zones               = local.stack.azure.zones
}

module "queue" {
  source = "./modules/queue"

  name_prefix         = local.stack.name_prefix
  safe_prefix         = local.safe_prefix
  unique_suffix       = local.unique_suffix
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
  runtime             = local.stack.runtime
  app_instances       = module.compute.app_instances
}

module "cache" {
  source = "./modules/cache"

  safe_prefix         = local.safe_prefix
  unique_suffix       = local.unique_suffix
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
  runtime             = local.stack.runtime
}

module "secrets" {
  source = "./modules/secrets"

  name_prefix         = local.stack.name_prefix
  resource_group_name = module.network.resource_group_name
  location            = module.network.location
  key_vault_name      = local.key_vault_name
  tenant_id           = try(local.stack.azure.tenant_id, "") != "" ? local.stack.azure.tenant_id : data.azurerm_client_config.current.tenant_id
  object_id           = data.azurerm_client_config.current.object_id
  api_domain          = local.api_domain
  secrets             = local.stack.secrets
}

module "access_outputs" {
  source = "../shared/access-outputs"

  cloud       = "azure"
  name_prefix = local.stack.name_prefix
  ssh         = local.stack.ssh
  instances   = module.compute.instances
  runtime     = local.runtime

  bastion_name     = local.stack.bastion_name
  app_names        = local.stack.app_names
  db_name          = local.stack.db_name
  app_url          = local.app_url
  app_domain       = local.app_domain
  image_registry   = local.stack.app.image_registry
  image_tag        = local.stack.app.image_tag
  api_url          = local.app_url
  ui_proxy_url     = "https://${try(local.stack.api.domain, local.app_domain)}/api"
  ui_history_url   = "https://${try(local.stack.api.domain, local.app_domain)}/history-api"
  cors_origin      = "https://${try(local.stack.ui.domain, local.stack.domain.name)}"
  known_hosts_file = "~/.ssh/known_hosts_azure_lab"
  secret_refs      = module.secrets.refs
  load_balancer = merge(module.load_balancer.load_balancer, {
    https_enabled = local.domain_enabled
  })
}
