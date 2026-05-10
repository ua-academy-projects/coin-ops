# locals.tf

locals {
  mappings = jsondecode(file("${path.module}/mappings.json"))

  workload_selectors = {
    for name, _ in var.workloads : name => ["workload-${name}"]
  }

  instances = {
    for name, cfg in var.workloads : name => {
      machine_type          = local.mappings.instance_type[cfg.instance_type]
      zone                  = local.mappings.placement[cfg.placement].instance_zone
      subnetwork            = var.subnetworks[cfg.subnet]
      tags                  = distinct(concat(cfg.tags, local.workload_selectors[name]))
      image                 = local.mappings.image_family[cfg.image_family]
      disk_size_gb          = cfg.disk_size_gb
      ssh_public_key_path   = var.ssh_public_key_path
      assign_public_ip      = cfg.public_ip
      can_ip_forward        = cfg.can_ip_forward
      service_account_email = try(var.service_accounts[cfg.service_account].email, null)
    }
  }
}
