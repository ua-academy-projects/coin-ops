locals {
  mappings = jsondecode(file("${path.module}/mappings.json"))

  delegated_subnet_cidr = cidrsubnet(var.network_cidr, 8, 255)

  location = var.location

  instance = {
    name                         = var.instance.name
    database_version             = local.mappings.database_version[var.instance.database_version]
    sku_name                     = local.mappings.instance_type[var.instance.instance_type]
    zone                         = local.mappings.placement[var.placement].instance_zone
    storage_mb                   = max(var.instance.disk_size * 1024, 32768)
    storage_auto_grow_enabled    = var.instance.disk_autoresize
    backup_retention_days        = var.instance.backup_enabled ? 7 : 1
    geo_redundant_backup_enabled = var.instance.availability_type == "regional"
    high_availability_mode       = var.instance.availability_type == "regional" ? "ZoneRedundant" : null
  }
}
