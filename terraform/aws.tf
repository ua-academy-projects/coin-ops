module "aws_network" {
  count    = local.aws_enabled ? 1 : 0
  source   = "./modules/cloud/aws/network"
  vpc_name = local.vpc_name
  vpc_cidr = local.vpc_cidr
  subnets  = local.subnets
  zone     = lookup(local.aws_cfg, "zone", "${local.aws_region}a")
}

module "aws_security_groups" {
  count          = local.aws_enabled ? 1 : 0
  source         = "./modules/cloud/aws/security_groups"
  vpc_id         = module.aws_network[0].vpc_id
  firewall_rules = local.firewall_rules
  egress_cidrs   = local.egress_cidrs
}

module "aws_instances" {
  count               = local.aws_enabled ? 1 : 0
  source              = "./modules/cloud/aws/instances"
  instances           = local.aws_instances_cfg
  defaults            = local.general
  cloud_defaults      = local.aws_cfg
  instance_sizes      = local.aws_instance_sizes
  subnet_ids          = module.aws_network[0].subnet_ids
  sg_ids              = module.aws_security_groups[0].sg_ids
  ssh_public_key      = local.ssh_public_key
  private_subnet_cidr = local.private_subnet_cidr
  username            = local.username
  ssh_port            = local.ssh_port
  project_name        = local.project_name
}

module "aws_nat_route" {
  count                    = local.aws_enabled && local.aws_has_nat_host ? 1 : 0
  source                   = "./modules/cloud/aws/nat_route"
  private_route_table_id   = module.aws_network[0].private_route_table_id
  nat_network_interface_id = module.aws_instances[0].instance_primary_network_interface_ids[local.aws_nat_host_name]
  destination_cidr         = local.nat_destination_cidr

  depends_on = [module.aws_instances]
}
