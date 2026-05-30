# locals.tf

locals {
  mappings = jsondecode(file("${path.module}/mappings.json"))

  instance = {
    identifier          = var.instance.name
    engine              = "postgres"
    engine_version      = local.mappings.database_version[var.instance.database_version]
    instance_class      = local.mappings.instance_type[var.instance.instance_type]
    allocated_storage   = var.instance.disk_size
    storage_type        = local.mappings.disk_type[var.instance.disk_type]
    multi_az            = local.mappings.availability_type[var.instance.availability_type]
    deletion_protection = var.instance.deletion_protection
    backup_retention    = var.instance.backup_enabled ? 7 : 0
    database_name       = var.database.name
    username            = var.user.name
  }
}
