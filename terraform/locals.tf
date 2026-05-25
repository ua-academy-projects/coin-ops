locals {
  is_gcp   = var.cloud_provider == "gcp"
  is_aws   = var.cloud_provider == "aws"
  is_azure = var.cloud_provider == "azure"

  # Load global mappings
  mappings = jsondecode(file("${path.module}/configs/mappings.json"))

  # Load environment or default configs
  is_default = var.environment == "default"

  # Path to the active environment directory
  env_dir = "${path.module}/configs/environments/${var.environment}"

  networking_config = jsondecode(file(local.is_default ? "${path.module}/configs/networking.json" : "${local.env_dir}/networking.json"))
  compute_config    = jsondecode(file(local.is_default ? "${path.module}/configs/compute.json" : "${local.env_dir}/compute.json"))
  lb_config         = jsondecode(file(local.is_default ? "${path.module}/configs/load_balancer.json" : "${local.env_dir}/load_balancer.json"))
  db_config         = jsondecode(file(local.is_default ? "${path.module}/configs/db.json" : (fileexists("${local.env_dir}/db.json") ? "${local.env_dir}/db.json" : "${path.module}/configs/db.json")))

  common_tags = local.is_default ? {
    environment = "default"
    managed_by  = "terraform"
  } : jsondecode(file("${local.env_dir}/tags.json"))

  # Global variables from loaded configs
  region_map = local.mappings.region_map
  region     = local.region_map[local.networking_config.region][var.cloud_provider]

  # DB mappings
  db_instance_class = local.mappings.db_instance_map[local.db_config.db_instance_class][var.cloud_provider]
  db_storage_type   = local.mappings.db_disk_type_map[local.db_config.db_storage_type][var.cloud_provider]

  # SSH Key
  ssh_public_key_content = fileexists(pathexpand(var.public_key_path)) ? file(pathexpand(var.public_key_path)) : ""
}
