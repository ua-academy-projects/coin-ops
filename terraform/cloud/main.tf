# ------------------------------------------------------------
# Azure
# ------------------------------------------------------------

module "azure_network" {
  source = "./modules/azure/network"
  count  = local.networks_by_cloud.azure != null ? 1 : 0

  resource_group_name = var.azure_resource_group_name
  network             = local.networks_by_cloud.azure
}

module "azure_security" {
  source = "./modules/azure/security"
  count  = local.networks_by_cloud.azure != null && length(local.workloads_by_cloud.azure) > 0 && length(local.security_rules) > 0 && local.default_cloud == "azure" ? 1 : 0

  resource_group_name = var.azure_resource_group_name
  location            = var.azure_location
  subnet_ids          = module.azure_network[0].subnetwork_ids
  subnets             = local.networks_by_cloud.azure.subnets
  workloads           = local.workloads_by_cloud.azure
  rules               = local.security_rules
}

module "azure_instances" {
  source = "./modules/azure/instances"
  count  = local.networks_by_cloud.azure != null && length(local.workloads_by_cloud.azure) > 0 ? 1 : 0

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
  count  = local.networks_by_cloud.azure != null && var.sql != null && local.default_cloud == "azure" ? 1 : 0

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
  count  = local.networks_by_cloud.azure != null && length(local.workloads_by_cloud.azure) > 0 && var.nat_route != null && local.default_cloud == "azure" ? 1 : 0

  resource_group_name = var.azure_resource_group_name
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
  count  = local.networks_by_cloud.gcp != null ? 1 : 0

  network = local.networks_by_cloud.gcp
  nat_route = local.default_cloud == "gcp" && length(local.workloads_by_cloud.gcp) > 0 && var.nat_route != null ? {
    name              = var.nat_route.name
    destination_range = var.nat_route.destination_range
    target_tags       = var.nat_route.target_tags
    next_hop_instance = module.gcp_instances[0].instance_self_links[var.nat_route.instance_workload]
  } : null
}

module "gcp_instances" {
  source = "./modules/gcp/instances"
  count  = local.networks_by_cloud.gcp != null && length(local.workloads_by_cloud.gcp) > 0 ? 1 : 0

  ssh_user            = "deployer"
  ssh_public_key_path = pathexpand(var.ssh_public_key_path)
  network_name        = module.gcp_network[0].network_name
  subnetworks         = module.gcp_network[0].subnetwork_names

  workloads = local.workloads_by_cloud.gcp
}

module "gcp_security" {
  source = "./modules/gcp/security"
  count  = local.networks_by_cloud.gcp != null && length(local.workloads_by_cloud.gcp) > 0 && length(local.security_rules) > 0 && local.default_cloud == "gcp" ? 1 : 0

  network_name       = module.gcp_network[0].network_name
  workload_selectors = module.gcp_instances[0].workload_selectors
  rules              = local.security_rules
}

module "gcp_secrets" {
  source = "./modules/gcp/secrets"
  count  = local.networks_by_cloud.gcp != null && length(local.workloads_by_cloud.gcp) > 0 && length(local.secrets) > 0 && local.default_cloud == "gcp" ? 1 : 0

  secrets          = local.secrets
  workloads        = local.workloads_by_cloud.gcp
  service_accounts = module.gcp_instances[0].service_accounts
}

module "gcp_sql" {
  source = "./modules/gcp/sql"
  count  = local.networks_by_cloud.gcp != null && var.sql != null && local.default_cloud == "gcp" ? 1 : 0

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
  count  = local.networks_by_cloud.aws != null ? 1 : 0

  network = local.networks_by_cloud.aws

  nat_route = local.default_cloud == "aws" && length(local.workloads_by_cloud.aws) > 0 && var.nat_route != null ? {
    name              = var.nat_route.name
    destination_range = var.nat_route.destination_range
    next_hop_instance = module.aws_instances[0].network_interface_ids[var.nat_route.instance_workload]
  } : null
}

module "aws_security" {
  source = "./modules/aws/security"
  count  = local.networks_by_cloud.aws != null && length(local.workloads_by_cloud.aws) > 0 && length(local.security_rules) > 0 && local.default_cloud == "aws" ? 1 : 0

  network_id     = module.aws_network[0].network_id
  workload_names = keys(local.workloads_by_cloud.aws)
  rules          = local.security_rules
}

module "aws_instances" {
  source = "./modules/aws/instances"
  count  = local.networks_by_cloud.aws != null && length(local.workloads_by_cloud.aws) > 0 ? 1 : 0

  subnetworks        = module.aws_network[0].subnetwork_ids
  security_group_ids = try(module.aws_security[0].security_group_ids, {})
  workloads          = local.workloads_by_cloud.aws
}

module "aws_sql" {
  source = "./modules/aws/sql"
  count  = local.networks_by_cloud.aws != null && var.sql != null && local.default_cloud == "aws" ? 1 : 0

  network_id            = module.aws_network[0].network_id
  private_subnet_ids    = module.aws_network[0].private_subnet_ids
  placement             = var.sql.placement
  db_password_secret_id = var.secrets["db_password"].secret_id

  instance = var.sql.instance
  database = var.sql.database
  user     = var.sql.user
}
