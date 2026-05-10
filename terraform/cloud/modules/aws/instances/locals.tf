# locals.tf

locals {
  mappings = jsondecode(file("${path.module}/mappings.json"))

  instances = {
    for name, cfg in var.workloads : name => {
      instance_type     = local.mappings.instance_type[cfg.instance_type]
      ami               = local.mappings.image_family[cfg.image_family]
      availability_zone = local.mappings.placement[cfg.placement].instance_zone
      subnet_id         = var.subnetworks[cfg.subnet]
      tags              = distinct(concat(cfg.tags, [name]))
      disk_size_gb      = cfg.disk_size_gb
      public_ip         = cfg.public_ip
    }
  }
}
