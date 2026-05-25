# =============================================================================
# modules/compute/main.tf
# =============================================================================
# Cloud-agnostic compute logic. Resources are separated into:
# - gcp.tf (Google Cloud)
# - aws.tf (Amazon Web Services)
# =============================================================================

locals {
  # ── Resolve all provider-specific values per VM ─────────────────────────────
  resolved_vms = {
    for name, vm in var.vms : name => {
      name           = name
      instance_type  = var.instance_type_map[vm.instance_size][var.cloud_provider]
      zone           = var.zone_map[vm.zone][var.cloud_provider]
      image          = var.image_map[vm.os_image][var.cloud_provider]
      disk_size_gb   = vm.disk_size_gb
      disk_type      = var.disk_type_map[vm.disk_type][var.cloud_provider]
      subnet_name    = vm.subnet_name
      private_ip     = vm.private_ip
      public_ip      = vm.public_ip
      tags           = vm.tags
      network_tags   = vm.network_tags
      startup_script = vm.startup_script
      spot           = vm.spot
    }
  }

  # ── SSH key metadata for GCP ────────────────────────────────────────────────
  ssh_key_metadata = (
    var.cloud_provider == "gcp" && var.ssh_public_key != ""
    ? "${var.ssh_user}:${var.ssh_public_key}"
    : ""
  )
}
