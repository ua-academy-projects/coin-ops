locals {
  mappings = jsondecode(file("${path.module}/mappings.json"))

  instances = {
    for name, cfg in var.workloads : name => {
      vm_size            = local.mappings.instance_type[cfg.instance_type]
      zone               = local.mappings.placement[cfg.placement].instance_zone
      subnet_id          = var.subnet_ids[cfg.subnet]
      image              = local.mappings.image_family[cfg.image_family]
      tags               = distinct(concat(cfg.tags, [name]))
      disk_size_gb       = max(cfg.disk_size_gb, 30)
      assign_public_ip   = cfg.public_ip
      can_ip_forward     = cfg.can_ip_forward
      application_sg_ids = lookup(var.application_security_group_ids, name, null) != null ? [var.application_security_group_ids[name]] : []
      managed_identity   = try(cfg.identity, cfg.service_account, null) != null
    }
  }
}
