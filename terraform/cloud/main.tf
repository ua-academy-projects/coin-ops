# ------------------------------------------------------------
# Azure
# ------------------------------------------------------------

module "azure_network" {
  source = "./modules/azure/network"
  count  = local.enable_azure_network ? 1 : 0

  resource_group_name = local.config_azure_resource_group
  network             = local.networks_by_cloud.azure
}

module "azure_security" {
  source = "./modules/azure/security"
  count  = local.enable_azure_security ? 1 : 0

  resource_group_name = local.config_azure_resource_group
  location            = local.config_azure_location
  subnet_ids          = module.azure_network[0].subnetwork_ids
  subnets             = local.networks_by_cloud.azure.subnets
  workloads           = local.workloads_by_cloud.azure
  rules               = local.config_security_rules
}

module "azure_instances" {
  source = "./modules/azure/instances"
  count  = local.enable_azure_workloads ? 1 : 0

  resource_group_name            = local.config_azure_resource_group
  location                       = local.config_azure_location
  ssh_user                       = local.config_ssh_user
  ssh_public_key_path            = pathexpand(local.config_ssh_public_key_path)
  key_vault_name                 = local.config_azure_key_vault_name
  subnet_ids                     = module.azure_network[0].subnetwork_ids
  application_security_group_ids = try(module.azure_security[0].application_security_group_ids, {})
  workloads                      = local.workloads_by_cloud.azure
}

module "azure_sql" {
  source = "./modules/azure/sql"
  count  = local.enable_azure_sql ? 1 : 0

  resource_group_name   = local.config_azure_resource_group
  location              = local.config_azure_location
  network_name          = module.azure_network[0].network_name
  network_id            = module.azure_network[0].network_id
  network_cidr          = local.networks_by_cloud.azure.cidr
  key_vault_name        = local.config_azure_key_vault_name
  db_password_secret_id = local.config_secrets["db_password"].secret_id
  placement             = local.config_sql.placement
  instance              = local.config_sql.instance
  database              = local.config_sql.database
  user                  = local.config_sql.user
}

module "azure_routing" {
  source = "./modules/azure/routing"
  count  = local.enable_azure_routing ? 1 : 0

  resource_group_name  = local.config_azure_resource_group
  route                = local.config_nat_route
  next_hop_private_ips = module.azure_instances[0].private_ips
  private_subnet_ids   = module.azure_network[0].private_subnet_ids
}

module "azure_monitoring" {
  source = "./modules/azure/monitoring"
  count  = local.default_cloud == "azure" ? 1 : 0

  name                                        = "coinops-monitoring"
  resource_group_name                         = local.config_azure_resource_group
  location                                    = local.config_azure_location
  vm_ids                                      = try(module.azure_instances[0].vm_ids, {})
  postgresql_server_id                        = try(module.azure_sql[0].server_id, null)
  vm_cpu_alert_enabled                        = true
  postgresql_cpu_alert_enabled                = true
  postgresql_storage_alert_enabled            = true
  postgresql_connections_alert_enabled        = true
  postgresql_failed_connections_alert_enabled = true
}


# ------------------------------------------------------------
# GCP
# ------------------------------------------------------------

module "gcp_network" {
  source = "./modules/gcp/network"
  count  = local.enable_gcp_network ? 1 : 0

  network = local.networks_by_cloud.gcp
}

module "gcp_instances" {
  source = "./modules/gcp/instances"
  count  = local.enable_gcp_workloads ? 1 : 0

  ssh_user            = local.config_ssh_user
  ssh_public_key_path = pathexpand(local.config_ssh_public_key_path)
  network_name        = module.gcp_network[0].network_name
  subnetworks         = module.gcp_network[0].subnetwork_names

  workloads = local.workloads_by_cloud.gcp
}

module "gcp_security" {
  source = "./modules/gcp/security"
  count  = local.enable_gcp_security ? 1 : 0

  network_name       = module.gcp_network[0].network_name
  workload_selectors = module.gcp_instances[0].workload_selectors
  rules              = local.config_security_rules
}

module "gcp_secrets" {
  source = "./modules/gcp/secrets"
  count  = local.enable_gcp_secrets ? 1 : 0

  secrets          = local.config_secrets
  workloads        = local.workloads_by_cloud.gcp
  service_accounts = module.gcp_instances[0].service_accounts
}

module "gcp_sql" {
  source = "./modules/gcp/sql"
  count  = local.enable_gcp_sql ? 1 : 0

  placement             = local.config_sql.placement
  network_name          = module.gcp_network[0].network_name
  db_password_secret_id = local.config_secrets["db_password"].secret_id

  instance = local.config_sql.instance
  database = local.config_sql.database
  user     = local.config_sql.user
}

module "gcp_routing" {
  source = "./modules/gcp/routing"
  count  = local.enable_gcp_routing ? 1 : 0

  network_name       = module.gcp_network[0].network_name
  route              = local.config_nat_route
  next_hop_instances = module.gcp_instances[0].instance_self_links
}



# ------------------------------------------------------------
# AWS
# ------------------------------------------------------------

module "aws_network" {
  source = "./modules/aws/network"
  count  = local.enable_aws_network ? 1 : 0

  network = local.networks_by_cloud.aws
}

module "aws_security" {
  source = "./modules/aws/security"
  count  = local.enable_aws_security ? 1 : 0

  network_id     = module.aws_network[0].network_id
  workload_names = keys(local.workloads_by_cloud.aws)
  rules          = local.config_security_rules
}

module "aws_instances" {
  source = "./modules/aws/instances"
  count  = local.enable_aws_workloads ? 1 : 0

  ssh_user            = local.config_ssh_user
  ssh_public_key_path = pathexpand(local.config_ssh_public_key_path)
  subnetworks         = module.aws_network[0].subnetwork_ids
  security_group_ids  = try(module.aws_security[0].security_group_ids, {})
  workloads           = local.workloads_by_cloud.aws
  secrets             = local.config_secrets
}

module "aws_sql" {
  source = "./modules/aws/sql"
  count  = local.enable_aws_sql ? 1 : 0

  network_id            = module.aws_network[0].network_id
  private_subnet_ids    = module.aws_network[0].private_subnet_ids
  placement             = local.config_sql.placement
  db_password_secret_id = local.config_secrets["db_password"].secret_id

  instance = local.config_sql.instance
  database = local.config_sql.database
  user     = local.config_sql.user
}

module "aws_routing" {
  source = "./modules/aws/routing"
  count  = local.enable_aws_routing ? 1 : 0

  network_id             = module.aws_network[0].network_id
  private_subnet_ids     = module.aws_network[0].private_subnet_ids
  route                  = local.config_nat_route
  next_hop_interface_ids = module.aws_instances[0].network_interface_ids
}
