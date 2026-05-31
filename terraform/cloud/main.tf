# ------------------------------------------------------------
# Azure
# ------------------------------------------------------------

module "azure_network" {
  source = "./modules/azure/network"
  count  = local.enable_azure_network ? 1 : 0

  resource_group_name = var.azure_resource_group_name
  network             = local.networks_by_cloud.azure
}

module "azure_security" {
  source = "./modules/azure/security"
  count  = local.enable_azure_security ? 1 : 0

  resource_group_name = var.azure_resource_group_name
  location            = var.azure_location
  subnet_ids          = module.azure_network[0].subnetwork_ids
  subnets             = local.networks_by_cloud.azure.subnets
  workloads           = local.workloads_by_cloud.azure
  rules               = local.security_rules
}

module "azure_instances" {
  source = "./modules/azure/instances"
  count  = local.enable_azure_workloads ? 1 : 0

  resource_group_name            = var.azure_resource_group_name
  location                       = var.azure_location
  ssh_public_key_path            = pathexpand(var.ssh_public_key_path)
  key_vault_name                 = var.azure_key_vault_name
  subnet_ids                     = module.azure_network[0].subnetwork_ids
  application_security_group_ids = try(module.azure_security[0].application_security_group_ids, {})
  workloads                      = local.workloads_by_cloud.azure
}

module "azure_sql" {
  source = "./modules/azure/sql"
  count  = local.enable_azure_sql ? 1 : 0

  resource_group_name   = var.azure_resource_group_name
  location              = var.azure_location
  network_name          = module.azure_network[0].network_name
  network_id            = module.azure_network[0].network_id
  network_cidr          = local.networks_by_cloud.azure.cidr
  key_vault_name        = var.azure_key_vault_name
  db_password_secret_id = var.secrets["db_password"].secret_id
  placement             = var.sql.placement
  instance              = var.sql.instance
  database              = var.sql.database
  user                  = var.sql.user
}

module "azure_routing" {
  source = "./modules/azure/routing"
  count  = local.enable_azure_routing ? 1 : 0

  resource_group_name = var.azure_resource_group_name
  route               = local.azure_nat_route
  private_subnet_ids  = module.azure_network[0].private_subnet_ids
}

# ------------------------------------------------------------
# GCP
# ------------------------------------------------------------

module "gcp_network" {
  source = "./modules/gcp/network"
  count  = local.enable_gcp_network ? 1 : 0

  network   = local.networks_by_cloud.gcp
  nat_route = local.gcp_nat_route
}

module "gcp_instances" {
  source = "./modules/gcp/instances"
  count  = local.enable_gcp_workloads ? 1 : 0

  ssh_user            = "deployer"
  ssh_public_key_path = pathexpand(var.ssh_public_key_path)
  network_name        = module.gcp_network[0].network_name
  subnetworks         = module.gcp_network[0].subnetwork_names

  workloads = local.workloads_by_cloud.gcp
}

module "gcp_security" {
  source = "./modules/gcp/security"
  count  = local.enable_gcp_security ? 1 : 0

  network_name       = module.gcp_network[0].network_name
  workload_selectors = module.gcp_instances[0].workload_selectors
  rules              = local.security_rules
}

module "gcp_secrets" {
  source = "./modules/gcp/secrets"
  count  = local.enable_gcp_secrets ? 1 : 0

  secrets          = local.secrets
  workloads        = local.workloads_by_cloud.gcp
  service_accounts = module.gcp_instances[0].service_accounts
}

module "gcp_sql" {
  source = "./modules/gcp/sql"
  count  = local.enable_gcp_sql ? 1 : 0

  placement             = var.sql.placement
  network_name          = module.gcp_network[0].network_name
  db_password_secret_id = var.secrets["db_password"].secret_id

  instance = var.sql.instance
  database = var.sql.database
  user     = var.sql.user
}

# ------------------------------------------------------------
# AWS
# ------------------------------------------------------------

module "aws_network" {
  source = "./modules/aws/network"
  count  = local.enable_aws_network ? 1 : 0

  network   = local.networks_by_cloud.aws
  nat_route = local.aws_nat_route
}

module "aws_security" {
  source = "./modules/aws/security"
  count  = local.enable_aws_security ? 1 : 0

  network_id     = module.aws_network[0].network_id
  workload_names = keys(local.workloads_by_cloud.aws)
  rules          = local.security_rules
}

module "aws_instances" {
  source = "./modules/aws/instances"
  count  = local.enable_aws_workloads ? 1 : 0

  subnetworks        = module.aws_network[0].subnetwork_ids
  security_group_ids = try(module.aws_security[0].security_group_ids, {})
  workloads          = local.workloads_by_cloud.aws
  secrets            = local.secrets
}

module "aws_sql" {
  source = "./modules/aws/sql"
  count  = local.enable_aws_sql ? 1 : 0

  network_id            = module.aws_network[0].network_id
  private_subnet_ids    = module.aws_network[0].private_subnet_ids
  placement             = var.sql.placement
  db_password_secret_id = var.secrets["db_password"].secret_id

  instance = var.sql.instance
  database = var.sql.database
  user     = var.sql.user
}
