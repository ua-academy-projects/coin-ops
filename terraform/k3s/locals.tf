# =============================================================================
# k3s/locals.tf
# =============================================================================
# Loads all JSON config files and resolves concrete GCP values via the shared
# mappings table (same pattern used by the root Terraform module).
#
# Config load order (environment overlay):
#   1. configs/<file>.json          ← base defaults
#   2. configs/environments/<env>/  ← environment overrides (if dir exists)
#
# Secrets are NOT loaded here — they are fetched from Secret Manager in
# secrets.tf and exposed via data sources.
# =============================================================================

locals {
  # ─── Shared mappings (re-use the global table) ──────────────────────────────
  mappings = jsondecode(file("${path.module}/../configs/mappings.json"))

  # ─── Environment overlay path ───────────────────────────────────────────────
  env_dir     = "${path.module}/configs/environments/${var.environment}"
  has_env_dir = fileexists("${local.env_dir}/.exists") # sentinel file pattern

  # ─── Config files (base, no overlay yet — add when multi-env is needed) ─────
  cluster_cfg    = jsondecode(file("${path.module}/configs/cluster.json"))
  networking_cfg = jsondecode(file("${path.module}/configs/networking.json"))
  compute_cfg    = jsondecode(file("${path.module}/configs/compute.json"))
  access_cfg     = jsondecode(file("${path.module}/configs/access.json"))

  # ─── Resolved project / region ──────────────────────────────────────────────
  # var.project_id overrides the JSON value (CI/CD injection point)
  project_id = var.project_id != "" ? var.project_id : local.cluster_cfg.project_id
  region     = local.mappings.region_map[local.cluster_cfg.region]["gcp"]

  # ─── Zones (concrete GCP zone strings) ──────────────────────────────────────
  zones = local.cluster_cfg.zones

  # ─── Networking ─────────────────────────────────────────────────────────────
  vpc_name            = local.networking_cfg.vpc_name
  public_subnet_cidr  = local.networking_cfg.public_subnet_cidr
  private_subnet_cidr = local.networking_cfg.private_subnet_cidr
  pods_cidr           = local.networking_cfg.pods_cidr
  services_cidr       = local.networking_cfg.services_cidr

  # ─── Bastion ────────────────────────────────────────────────────────────────
  bastion_machine_type = local.mappings.instance_type_map[local.compute_cfg.bastion.instance_size]["gcp"]
  bastion_image        = local.mappings.image_map[local.compute_cfg.bastion.os_image]["gcp"]

  # ─── k3s Nodes ──────────────────────────────────────────────────────────────
  k3s_node_count   = length(local.compute_cfg.nodes)
  k3s_machine_type = local.mappings.instance_type_map[local.compute_cfg.nodes[0].instance_size]["gcp"]
  k3s_disk_size_gb = local.compute_cfg.nodes[0].disk_size_gb
  k3s_image        = local.mappings.image_map[local.compute_cfg.nodes[0].os_image]["gcp"]
  k3s_version      = local.cluster_cfg.k3s_version

  # ─── Helm chart versions ─────────────────────────────────────────────────────
  cilium_version        = local.cluster_cfg.helm.cilium_version
  cert_manager_version  = local.cluster_cfg.helm.cert_manager_version
  nginx_ingress_version = local.cluster_cfg.helm.nginx_ingress_version
  headlamp_version      = local.cluster_cfg.helm.headlamp_version
  prometheus_version    = local.cluster_cfg.helm.prometheus_version
  loki_version          = local.cluster_cfg.helm.loki_version
  tailscale_version     = local.cluster_cfg.helm.tailscale_version

  # ─── IAP access ─────────────────────────────────────────────────────────────
  iap_allowed_members = local.access_cfg.iap_allowed_members

  # ─── Common labels (applied to all GCP resources) ───────────────────────────
  common_labels = {
    environment = var.environment
    managed_by  = "terraform"
    cluster     = "k3s-ha"
  }
}
