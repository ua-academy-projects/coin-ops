# =============================================================================
# gke/network.tf
# =============================================================================
# Standalone VPC for the GKE cluster.
#
# Production reasoning:
#   • A dedicated VPC isolates the Kubernetes workload network from the legacy
#     VM network, making firewall rules, peering, and routing easier to reason
#     about and audit.
#   • Cloud NAT lets private nodes pull images and OS updates without public IPs.
#   • Private Google Access lets nodes reach googleapis.com internally (no NAT hop).
# =============================================================================

# ─── VPC ─────────────────────────────────────────────────────────────────────
resource "google_compute_network" "gke_vpc" {
  project                 = var.project_id
  name                    = var.vpc_name
  auto_create_subnetworks = false # Custom-mode VPC — we define every subnet.
  description             = "GKE VPC for ${var.cluster_name}. Managed by Terraform."
}

# ─── Primary subnet + secondary ranges ───────────────────────────────────────
# Secondary ranges are mandatory for VPC-native (alias IP) clusters.
resource "google_compute_subnetwork" "gke_subnet" {
  project       = var.project_id
  name          = var.subnet_name
  region        = var.region
  network       = google_compute_network.gke_vpc.id
  ip_cidr_range = var.subnet_cidr

  # Nodes can reach Google APIs (Artifact Registry, Secret Manager…) without NAT.
  private_ip_google_access = true

  # Pod IPs — each node gets a /24 slice of this range by default.
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  # Service ClusterIPs.
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

# ─── Cloud Router ─────────────────────────────────────────────────────────────
resource "google_compute_router" "gke_router" {
  project = var.project_id
  name    = "${var.vpc_name}-router"
  region  = var.region
  network = google_compute_network.gke_vpc.id
  description = "Cloud Router for GKE NAT. Managed by Terraform."
}

# ─── Cloud NAT ────────────────────────────────────────────────────────────────
# Private nodes need NAT to pull container images from Docker Hub, ghcr.io, etc.
# Traffic to googleapis.com goes through Private Google Access (no NAT).
resource "google_compute_router_nat" "gke_nat" {
  project = var.project_id
  name    = "${var.vpc_name}-nat"
  router  = google_compute_router.gke_router.name
  region  = var.region

  # AUTO_ONLY: GCP manages the external IP pool (simpler ops, no quota worries).
  nat_ip_allocate_option = "AUTO_ONLY"

  # Only NAT traffic from the GKE subnet; leave other subnets (if any) unaffected.
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.gke_subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY" # Log only NAT failures to keep log volume manageable.
  }
}

# ─── Firewall: allow GKE control-plane → node webhook ports ──────────────────
# The control-plane must reach admission webhooks (8443/9443) and the Kubelet
# metrics endpoint (10250) on nodes. Without this rule, webhook-based add-ons
# (cert-manager, Istio, etc.) will fail to inject sidecars or validate objects.
resource "google_compute_firewall" "gke_master_webhooks" {
  project     = var.project_id
  name        = "${var.cluster_name}-master-webhooks"
  network     = google_compute_network.gke_vpc.name
  description = "Allow GKE control-plane to reach node webhook and metrics ports."
  direction   = "INGRESS"
  priority    = 1000

  allow {
    protocol = "tcp"
    ports    = ["8443", "9443", "10250"]
  }

  # Source: the private /28 block reserved for the control-plane.
  source_ranges = [var.master_ipv4_cidr_block]

  # Target: only GKE nodes (tagged by the node pool config in cluster.tf).
  target_tags = ["gke-${var.cluster_name}"]
}
