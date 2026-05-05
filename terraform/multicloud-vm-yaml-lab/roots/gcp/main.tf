module "network" {
  source = "../../modules/network"

  region  = local.gcp_location.region
  network = local.network
}

module "vms" {
  source = "../../modules/gcp-vms"

  zone       = local.gcp_location.zone
  network    = module.network.network_self_link
  subnetwork = module.network.subnetwork_self_link

  defaults  = local.gcp_vm_defaults
  instances = local.gcp_instances
}

module "firewall" {
  source = "../../modules/firewall"

  name_prefix             = local.raw.name_prefix
  network                 = module.network.network_self_link
  ssh_source_ranges       = local.raw.firewall.ssh_source_ranges
  bastion_target_tags     = local.bastion_target_tags
  private_target_tags     = local.private_target_tags
  allow_icmp_from_bastion = local.raw.firewall.allow_icmp_from_bastion
}
