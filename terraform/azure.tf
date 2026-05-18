data "azurerm_key_vault" "shared" {
  count               = local.read_azure_secret_backend ? 1 : 0
  name                = local.azure_key_vault_name
  resource_group_name = local.azure_resource_group_name
}

data "azurerm_key_vault_secret" "db_secrets" {
  count        = local.read_azure_secret_backend ? 1 : 0
  name         = local.db_secret_name
  key_vault_id = data.azurerm_key_vault.shared[0].id
}

data "azurerm_key_vault_secret" "app_secrets" {
  count        = local.read_azure_secret_backend ? 1 : 0
  name         = local.app_secret_name
  key_vault_id = data.azurerm_key_vault.shared[0].id
}

module "azure_network" {
  count               = local.azure_enabled ? 1 : 0
  source              = "./modules/cloud/azure/network"
  vpc_name            = local.azure_vpc_name
  vpc_cidr            = local.azure_vpc_cidr
  subnets             = local.azure_subnets
  location            = local.azure_location
  resource_group_name = local.azure_resource_group_name
}

module "azure_security_groups" {
  count               = local.azure_enabled ? 1 : 0
  source              = "./modules/cloud/azure/security_groups"
  resource_group_name = module.azure_network[0].resource_group_name
  location            = local.azure_location
  firewall_rules      = local.firewall_rules
  egress_cidrs        = local.egress_cidrs
}

module "azure_instances" {
  count               = local.azure_compute_enabled ? 1 : 0
  source              = "./modules/cloud/azure/instances"
  instances           = local.azure_instances_cfg
  defaults            = local.general
  cloud_defaults      = local.azure_cfg
  instance_sizes      = local.azure_instance_sizes
  subnet_ids          = module.azure_network[0].subnet_ids
  nsg_ids             = module.azure_security_groups[0].nsg_ids
  asg_ids             = module.azure_security_groups[0].asg_ids
  ssh_public_key      = local.ssh_public_key
  private_subnet_cidr = local.azure_private_subnet_cidr
  vpc_cidr            = local.azure_vpc_cidr
  username            = local.username
  ssh_port            = local.ssh_port
  project_name        = local.project_name
  resource_group_name = module.azure_network[0].resource_group_name
  location            = local.azure_location
}

module "azure_nat_route" {
  count               = local.azure_compute_enabled && local.azure_has_route_host ? 1 : 0
  source              = "./modules/cloud/azure/nat_route"
  resource_group_name = module.azure_network[0].resource_group_name
  location            = local.azure_location
  private_subnet_ids  = module.azure_network[0].private_subnet_ids
  public_subnet_ids   = module.azure_network[0].public_subnet_ids
  route_table_name    = local.nat_route_name
  private_routes      = local.azure_private_route_specs
  public_routes       = local.azure_public_route_specs
  next_hop_ip         = try(module.azure_instances[0].instance_ips[local.azure_route_host_name].private_ip, "")

  depends_on = [module.azure_instances]
}

module "azure_database" {
  count                 = local.azure_enabled && local.database_enabled ? 1 : 0
  source                = "./modules/cloud/azure/database"
  project_name          = local.project_name
  resource_group_name   = module.azure_network[0].resource_group_name
  location              = local.azure_location
  virtual_network_id    = module.azure_network[0].network_id
  subnet_id             = module.azure_network[0].database_subnet_id
  db_password           = local.effective_db_password
  db_name               = local.db_name
  db_username           = local.db_username
  db_port               = local.db_port
  sku_name              = try(local.azure_db_profile.sku_name, "B_Standard_B1ms")
  storage_mb            = try(local.azure_db_profile.storage_mb, 32768)
  backup_retention_days = try(local.azure_db_profile.backup_retention_days, 7)
}

module "azure_secrets" {
  count                = local.write_azure_secret_backend ? 1 : 0
  source               = "./modules/cloud/azure/secrets"
  resource_group_name  = module.azure_network[0].resource_group_name
  location             = local.azure_location
  tenant_id            = local.azure_tenant_id
  key_vault_name       = local.azure_key_vault_name
  db_secret_name       = local.db_secret_name
  app_secret_name      = local.app_secret_name
  db_password          = local.effective_db_password
  rabbitmq_password    = local.effective_rabbitmq_password
  ghcr_token           = local.effective_ghcr_token
  cloudflare_api_token = local.effective_cloudflare_api_token
  tailscale_auth_key   = local.effective_tailscale_auth_key
}
