module "aws" {
  count  = local.is_aws ? 1 : 0
  source = "./modules/aws-cloud-native"

  config = local.config
}

module "gcp" {
  count  = local.is_gcp ? 1 : 0
  source = "./modules/gcp-stack"

  config = local.config
}
