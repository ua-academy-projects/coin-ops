locals {
  config       = var.config
  name_prefix  = local.config.name_prefix
  network_key  = local.config.defaults.network
  network_raw  = local.config.networks[local.network_key]
  gcp_location = local.config.catalog.locations[local.config.location].gcp

  network = {
    name        = local.network_raw.name
    subnet_name = local.network_raw.subnet_name
    cidr        = try(local.network_raw.gcp_subnet_cidr, local.network_raw.cidr)
  }

  instances = {
    for name, vm in local.config.instances : name => {
      private_ip   = vm.private_ip
      public_ip    = local.config.roles[vm.role].public_ip
      tags         = local.config.roles[vm.role].tags
      machine_type = local.config.catalog.sizes[lookup(vm, "size", local.config.defaults.size)].gcp
      image        = local.config.catalog.images[lookup(vm, "image", local.config.defaults.image)].gcp
      disk_size_gb = lookup(vm, "disk_size_gb", local.config.defaults.disk_size_gb)
    }
  }

  bastion_name = local.config.app.nodes.bastion
  private_tags = distinct(flatten([
    for name, vm in local.instances : vm.tags if name != local.bastion_name
  ]))
}

module "network" {
  source = "../network"

  region  = local.gcp_location.region
  network = local.network
}

module "vms" {
  source = "../gcp-vms"

  zone       = local.gcp_location.zone
  network    = module.network.network_self_link
  subnetwork = module.network.subnetwork_self_link

  defaults = {
    machine_type        = local.config.catalog.sizes[local.config.defaults.size].gcp
    image               = local.config.catalog.images[local.config.defaults.image].gcp
    disk_size_gb        = local.config.defaults.disk_size_gb
    ssh_user            = local.config.ssh.user
    ssh_public_key_path = local.config.ssh.public_key_path
  }
  instances = local.instances
}

module "firewall" {
  source = "../firewall"

  name_prefix             = local.name_prefix
  network                 = module.network.network_self_link
  ssh_source_ranges       = local.config.firewall.ssh_source_ranges
  bastion_target_tags     = local.config.roles.bastion.tags
  private_target_tags     = local.private_tags
  allow_icmp_from_bastion = local.config.firewall.allow_icmp_from_bastion
}
