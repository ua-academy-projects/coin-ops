module "aws" {
  count  = local.is_aws ? 1 : 0
  source = "./modules/aws-cloud-native"

  stack       = local.stack
  db_password = var.db_password
}

module "gcp" {
  count  = local.is_gcp ? 1 : 0
  source = "./modules/gcp-stack"

  stack       = local.stack
  db_password = var.db_password
}

module "azure" {
  count  = local.is_azure ? 1 : 0
  source = "./modules/azure-stack"

  stack       = local.stack
  db_password = var.db_password
}

module "aws_ui" {
  count  = local.split_ui_backend && local.ui_cloud == "aws" ? 1 : 0
  source = "./modules/aws-ui"

  stack            = local.stack
  known_hosts_file = "~/.ssh/known_hosts_${local.cloud}_lab"
}

module "gcp_ui" {
  count  = local.split_ui_backend && local.ui_cloud == "gcp" ? 1 : 0
  source = "./modules/gcp-ui"

  stack            = local.stack
  known_hosts_file = "~/.ssh/known_hosts_${local.cloud}_lab"
}
