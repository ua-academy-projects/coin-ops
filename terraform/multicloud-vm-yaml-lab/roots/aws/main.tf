module "network" {
  source = "../../modules/aws-network"

  name_prefix       = local.raw.name_prefix
  network           = local.network
  availability_zone = local.aws_location.availability_zone
}

module "firewall" {
  source = "../../modules/aws-firewall"

  name_prefix = local.raw.name_prefix
  vpc_id      = module.network.vpc_id

  ssh_source_ranges       = local.raw.firewall.ssh_source_ranges
  allow_icmp_from_bastion = local.raw.firewall.allow_icmp_from_bastion
}

module "vms" {
  source = "../../modules/aws-vms"

  subnet_id           = module.network.subnet_id
  availability_zone   = local.aws_location.availability_zone
  instances           = local.aws_instances
  image_catalog       = local.aws_image_catalog
  ssh_public_key_path = local.raw.ssh.public_key_path

  security_groups = {
    bastion = module.firewall.bastion_security_group_id
    private = module.firewall.private_security_group_id
  }
}
