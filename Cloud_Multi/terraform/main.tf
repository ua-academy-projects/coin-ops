locals {
  config  = yamldecode(file("${path.module}/config.yaml"))
  general = local.config.general
}

module "gcp_network" {
  source = "./modules/gcp_network"

  cloud  = local.general.cloud
  region = local.general.gcp_region
}

module "gcp_security" {
  source = "./modules/gcp_security"

  cloud    = local.general.cloud
  vpc_name = module.gcp_network.vpc_name
  ssh_port = local.general.ssh_port
}

module "gcp_vm" {
  source = "./modules/gcp_vm"

  cloud          = local.general.cloud
  vms            = local.config.vms
  sizes          = local.config.sizes
  zone           = local.general.gcp_zone
  image          = local.general.image.gcp
  default_disk   = local.general.disk_size
  subnetwork     = module.gcp_network.subnet_id
  ops_user       = local.general.ops_user
  ssh_port       = local.general.ssh_port
  ssh_public_key = file("${pathexpand("~")}/.ssh/id_ed25519.pub")
}

module "aws_network" {
  source = "./modules/aws_network"

  cloud = local.general.cloud
}

module "aws_security" {
  source = "./modules/aws_security"

  cloud    = local.general.cloud
  vpc_id   = module.aws_network.vpc_id
  ssh_port = local.general.ssh_port
}

module "aws_vm" {
  source = "./modules/aws_vm"

  cloud             = local.general.cloud
  vms               = local.config.vms
  sizes             = local.config.sizes
  ami               = local.general.image.aws
  default_disk      = local.general.disk_size
  ops_user          = local.general.ops_user
  ssh_port          = local.general.ssh_port
  ssh_public_key    = file("${pathexpand("~")}/.ssh/id_ed25519.pub")
  public_subnet_id  = module.aws_network.public_subnet_id
  private_subnet_id = module.aws_network.private_subnet_id
  jump_host_sg_id   = module.aws_security.jump_host_sg_id
  internal_sg_id    = module.aws_security.internal_sg_id
}