locals {
  raw_config = yamldecode(file("${path.module}/config.yaml"))

  config = merge(local.raw_config, {
    general = merge(local.raw_config.general, {
      db_password = var.db_password
    })
  })

  general  = local.config.general
  cloud    = local.general.cloud
  location = local.general.location

  active_location = local.config.locations[local.location][local.cloud]
}

module "gcp_network" {
  source = "./modules/gcp_network"
  config = local.config
}

module "gcp_security" {
  source   = "./modules/gcp_security"
  config   = local.config
  vpc_name = module.gcp_network.vpc_name
}

module "gcp_vm" {
  source         = "./modules/gcp_vm"
  config         = local.config
  subnetwork     = module.gcp_network.subnet_id
  ssh_public_key = file("${pathexpand("~")}/.ssh/id_ed25519.pub")
}

module "aws_network" {
  source = "./modules/aws_network"
  config = local.config
}

module "aws_security" {
  source = "./modules/aws_security"
  config = local.config
  vpc_id = module.aws_network.vpc_id
}

module "aws_vm" {
  source            = "./modules/aws_vm"
  config            = local.config
  ssh_public_key    = file("${pathexpand("~")}/.ssh/id_ed25519.pub")
  public_subnet_id  = module.aws_network.public_subnet_id
  private_subnet_id = module.aws_network.private_subnet_id
  jump_host_sg_id   = module.aws_security.jump_host_sg_id
  internal_sg_id    = module.aws_security.internal_sg_id
  web_sg_id         = module.aws_security.web_sg_id
}

module "aws_lb" {
  source = "./modules/aws_lb"

  config = local.config

  vpc_id             = module.aws_network.vpc_id
  public_subnet_id   = module.aws_network.public_subnet_id
  public_subnet_b_id = module.aws_network.public_subnet_b_id

  ui_instance_id = module.aws_vm.ui_instance_id
}

module "aws_rds" {
  source              = "./modules/aws_rds"
  config              = local.config
  private_subnet_id   = module.aws_network.private_subnet_id
  private_subnet_b_id = module.aws_network.private_subnet_b_id
  rds_sg_id           = module.aws_security.rds_sg_id
}

output "alb_dns_name" {
  value = module.aws_lb.alb_dns_name
}