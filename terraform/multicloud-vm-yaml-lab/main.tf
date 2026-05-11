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
