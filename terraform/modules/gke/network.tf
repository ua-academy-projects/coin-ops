# =============================================================================
# modules/gke/network.tf
# =============================================================================
# GKE-specific networking resources.
#
# This module *reuses* the VPC and subnet created by the existing
# modules/networking module. It only adds the secondary IP ranges that
# VPC-native clusters require for Pods and Services.
#
# Why VPC-native (alias IPs)?
#   • Pod IPs are directly routable within the VPC — no NAT between pods.
#   • Required for GKE Dataplane V2 / eBPF-based networking.
#   • Enables GKE Network Policy.
# =============================================================================

# ─── Secondary ranges on the GKE subnet ──────────────────────────────────────
# We patch the *existing* subnetwork to add secondary ranges rather than
# creating a brand-new subnetwork, so the GKE cluster and the rest of the
# Coin Ops infra share the same subnet.
resource "google_compute_subnetwork" "gke_subnet" {
  project       = var.project_id
  name          = var.subnet_name
  region        = var.region
  network       = var.network_name
  ip_cidr_range = var.subnet_cidr

  # Enable Private Google Access so nodes can reach Google APIs without NAT.
  private_ip_google_access = true

  # ── Pod and Service secondary ranges ───────────────────────────────────────
  # /17 gives ~32 k Pod IPs (one /24 per node by default).
  # /22 gives ~1 k Service ClusterIPs.
  secondary_ip_range {
    range_name    = var.pods_range_name
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = var.services_range_name
    ip_cidr_range = var.services_cidr
  }
}

# ─── Firewall: allow control-plane webhook traffic ────────────────────────────
# The GKE control plane (master CIDR) must be able to reach node ports used by
# admission webhooks (typically 8443 / 9443) and Kubernetes metrics (10250).
resource "google_compute_firewall" "gke_master_webhooks" {
  project     = var.project_id
  name        = "${var.cluster_name}-master-webhooks"
  network     = var.network_name
  description = "Allow GKE control plane to reach node webhook ports."
  direction   = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["8443", "9443", "10250"]
  }

  source_ranges = [var.master_ipv4_cidr_block]
  target_tags   = ["gke-${var.cluster_name}"]
}
