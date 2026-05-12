# locals.tf

locals {
  mappings = jsondecode(file("${path.module}/mappings.json"))

  region = local.mappings.placement[var.placement].region

  instance = {
    name                        = var.instance.name
    edition                     = local.mappings.edition[var.instance.edition]
    database_version            = local.mappings.database_version[var.instance.database_version]
    tier                        = local.mappings.instance_type[var.instance.instance_type]
    availability_type           = local.mappings.availability_type[var.instance.availability_type]
    disk_type                   = local.mappings.disk_type[var.instance.disk_type]
    disk_size                   = var.instance.disk_size
    disk_autoresize             = var.instance.disk_autoresize
    deletion_protection         = var.instance.deletion_protection
    backup_enabled              = var.instance.backup_enabled
    pitr_enabled                = var.instance.pitr_enabled
    private_range_name          = var.instance.private_range_name
    private_range_cidr          = var.instance.private_range_cidr
    deletion_protection_enabled = var.instance.deletion_protection
  }
}
