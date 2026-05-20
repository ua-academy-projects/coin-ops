# ------------------------------------------------------------
# Azure
# ------------------------------------------------------------

module "azure_network" {
  source = "./modules/azure/network"
  count  = var.cloud == "azure" ? 1 : 0

  resource_group_name = local.azure.resource_group_name
  network             = var.network
}

module "azure_security" {
  source = "./modules/azure/security"
  count  = var.cloud == "azure" ? 1 : 0

  resource_group_name = local.azure.resource_group_name
  location            = local.azure.location
  subnet_ids          = module.azure_network[0].subnetwork_ids
  subnets             = var.network.subnets
  workloads           = var.workloads
  rules               = var.security_rules
}

module "azure_instances" {
  source = "./modules/azure/instances"
  count  = var.cloud == "azure" ? 1 : 0

  resource_group_name            = local.azure.resource_group_name
  location                       = local.azure.location
  ssh_public_key_path            = pathexpand(var.ssh_public_key_path)
  key_vault_name                 = local.azure.key_vault_name
  subnet_ids                     = module.azure_network[0].subnetwork_ids
  application_security_group_ids = module.azure_security[0].application_security_group_ids
  workloads                      = var.workloads
}

module "azure_sql" {
  source = "./modules/azure/sql"
  count  = var.cloud == "azure" && var.sql != null ? 1 : 0

  resource_group_name   = local.azure.resource_group_name
  location              = local.azure.location
  network_name          = module.azure_network[0].network_name
  network_id            = module.azure_network[0].network_id
  network_cidr          = var.network.cidr
  key_vault_name        = local.azure.key_vault_name
  db_password_secret_id = local.normalized_secrets["db_password"].secret_id
  placement             = var.sql.placement
  instance              = var.sql.instance
  database              = var.sql.database
  user                  = var.sql.user
}

module "azure_routing" {
  source = "./modules/azure/routing"
  count  = var.cloud == "azure" && var.nat_route != null ? 1 : 0

  resource_group_name = local.azure.resource_group_name
  route = {
    name              = var.nat_route.name
    destination_range = var.nat_route.destination_range
    next_hop_ip       = module.azure_instances[0].private_ips[var.nat_route.instance_workload]
  }
  private_subnet_ids = module.azure_network[0].private_subnet_ids
}

# ------------------------------------------------------------
# GCP
# ------------------------------------------------------------

module "gcp_network" {
  source = "./modules/gcp/network"
  count  = var.cloud == "gcp" ? 1 : 0

  network = var.network
  nat_route = var.cloud == "gcp" && var.nat_route != null ? {
    name              = var.nat_route.name
    destination_range = var.nat_route.destination_range
    target_tags       = var.nat_route.target_tags
    next_hop_instance = module.gcp_instances[0].instance_self_links[var.nat_route.instance_workload]
  } : null
}

module "gcp_instances" {
  source = "./modules/gcp/instances"
  count  = var.cloud == "gcp" ? 1 : 0

  ssh_user            = "deployer"
  ssh_public_key_path = pathexpand(var.ssh_public_key_path)
  network_name        = module.gcp_network[0].network_name
  subnetworks         = module.gcp_network[0].subnetwork_names

  workloads = var.workloads
}

module "gcp_security" {
  source = "./modules/gcp/security"
  count  = var.cloud == "gcp" ? 1 : 0

  network_name       = module.gcp_network[0].network_name
  workload_selectors = module.gcp_instances[0].workload_selectors
  rules              = var.security_rules
}

module "gcp_secrets" {
  source = "./modules/gcp/secrets"
  count  = var.cloud == "gcp" ? 1 : 0

  secrets          = local.normalized_secrets
  workloads        = var.workloads
  service_accounts = module.gcp_instances[0].service_accounts
}

module "gcp_sql" {
  source = "./modules/gcp/sql"
  count  = var.cloud == "gcp" && var.sql != null ? 1 : 0

  placement             = var.sql.placement
  network_name          = module.gcp_network[0].network_name
  db_password_secret_id = local.normalized_secrets["db_password"].secret_id

  instance = var.sql.instance
  database = var.sql.database
  user     = var.sql.user
}

# ------------------------------------------------------------
# AWS
# ------------------------------------------------------------

module "aws_network" {
  source = "./modules/aws/network"
  count  = var.cloud == "aws" ? 1 : 0

  network = var.network
}

module "aws_security" {
  source = "./modules/aws/security"
  count  = var.cloud == "aws" ? 1 : 0

  network_id     = module.aws_network[0].network_id
  workload_names = keys(var.workloads)
  rules          = var.security_rules
}

module "aws_instances" {
  source = "./modules/aws/instances"
  count  = var.cloud == "aws" ? 1 : 0

  subnetworks        = module.aws_network[0].subnetwork_ids
  security_group_ids = module.aws_security[0].security_group_ids
  workloads          = var.workloads
}
