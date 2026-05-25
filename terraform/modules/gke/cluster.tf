# =============================================================================
# modules/gke/cluster.tf
# =============================================================================
# GKE Regional Private Cluster + custom auto-scaling node pool.
#
# Key production decisions:
#   Regional cluster   — control-plane and nodes span 3 zones → no single AZ SPOF.
#   Private nodes      — worker nodes have no external IPs (egress via Cloud NAT).
#   Private endpoint   — control-plane API is only reachable from authorized CIDRs.
#   Workload Identity  — the safest way for Pods to call Google APIs (no key files).
#   Shielded nodes     — protect against rootkit / bootkit attacks.
#   Release channel    — GKE manages safe, incremental Kubernetes upgrades.
#   No default pool    — default pool is removed immediately; only our custom pool exists.
#   Binary Authorization (optional, set to DISABLED here but infrastructure is ready).
# =============================================================================

resource "google_container_cluster" "this" {
  provider = google-beta # beta required for some features (e.g. Dataplane V2)

  project  = var.project_id
  name     = var.cluster_name
  location = var.region # regional = HA across zones

  # ── Network ────────────────────────────────────────────────────────────────
  network    = var.network_name
  subnetwork = google_compute_subnetwork.gke_subnet.name

  # VPC-native routing (alias IPs) — required for Network Policy and Dataplane V2.
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # ── Private cluster ────────────────────────────────────────────────────────
  private_cluster_config {
    # Nodes receive no external IPs.
    enable_private_nodes = true

    # Lock down the control-plane API to private access.
    # Set enable_private_endpoint = false if you need kubectl from developer machines
    # via authorized_networks below, which is the recommended hybrid approach.
    enable_private_endpoint = false

    master_ipv4_cidr_block = var.master_ipv4_cidr_block
  }

  # ── Control-plane authorized networks ──────────────────────────────────────
  # Restrict who can reach the K8s API server. Always include your CI/CD runner
  # CIDR and VPN/bastion CIDR here. Never use 0.0.0.0/0 in production.
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # ── Kubernetes version / release channel ───────────────────────────────────
  min_master_version = var.kubernetes_version

  release_channel {
    # REGULAR: tested releases ~every 2 months. Best balance for production.
    channel = var.release_channel
  }

  # ── Remove the default node pool immediately ────────────────────────────────
  # We manage our own pool below; the initial_node_count is required for the API
  # call but the default pool is deleted as soon as Terraform creates the cluster.
  remove_default_node_pool = true
  initial_node_count       = 1

  # ── Workload Identity ──────────────────────────────────────────────────────
  # Maps K8s ServiceAccounts to Google ServiceAccounts — the recommended
  # alternative to downloading and mounting service-account key files.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # ── Add-ons ────────────────────────────────────────────────────────────────
  addons_config {
    # HTTP load balancing: provisions GCLB via Ingress resources.
    http_load_balancing {
      disabled = false
    }

    # Horizontal Pod Autoscaler.
    horizontal_pod_autoscaling {
      disabled = false
    }

    # GCE Persistent Disk CSI Driver — required for ReadWriteOnce PVCs.
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }

    # DNS cache for faster Pod DNS resolution.
    dns_cache_config {
      enabled = true
    }
  }

  # ── Dataplane V2 (eBPF-based networking) ───────────────────────────────────
  # Replaces kube-proxy with eBPF; required for fine-grained Network Policy.
  datapath_provider = "ADVANCED_DATAPATH"

  # ── Network Policy ─────────────────────────────────────────────────────────
  # Enables the Kubernetes NetworkPolicy API (enforced by Dataplane V2).
  network_policy {
    enabled  = true
    provider = "CALICO" # ignored when using ADVANCED_DATAPATH but required by API
  }

  # ── Shielded GKE nodes ─────────────────────────────────────────────────────
  enable_shielded_nodes = true

  # ── Logging & monitoring ───────────────────────────────────────────────────
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # ── Maintenance window ─────────────────────────────────────────────────────
  # Maintenance during low-traffic hours (UTC). Adjust to your region's off-peak.
  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T02:00:00Z"
      end_time   = "2024-01-01T06:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  # ── Resource labels ────────────────────────────────────────────────────────
  resource_labels = merge(var.common_tags, {
    cluster = var.cluster_name
  })

  # Prevents accidental deletion of a running production cluster.
  deletion_protection = true

  lifecycle {
    ignore_changes = [
      # Terraform may want to change this on each plan because GKE normalises it.
      initial_node_count,
      # Allow GKE to auto-upgrade without Terraform drift.
      min_master_version,
    ]
  }
}

# =============================================================================
# Custom Node Pool
# =============================================================================
resource "google_container_node_pool" "main" {
  provider = google-beta

  project    = var.project_id
  name       = var.node_pool_name
  cluster    = google_container_cluster.this.name
  location   = var.region # regional pool — nodes spread across zones automatically

  # ── Cluster Autoscaler ─────────────────────────────────────────────────────
  # min/max are *per zone*. A 3-zone regional cluster with max=5 can scale to 15 nodes.
  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  initial_node_count = var.initial_node_count

  # ── Upgrade strategy ───────────────────────────────────────────────────────
  # Surge upgrades replace nodes one by one, keeping the pool available.
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  # ── Node management ────────────────────────────────────────────────────────
  management {
    auto_repair  = true  # GKE auto-repairs unhealthy nodes.
    auto_upgrade = true  # GKE keeps node version in sync with control-plane channel.
  }

  node_config {
    machine_type = var.node_machine_type
    disk_size_gb = var.node_disk_size_gb
    disk_type    = var.node_disk_type

    # Use the dedicated least-privilege SA created in iam.tf.
    service_account = google_service_account.gke_node_sa.email

    # Minimal OAuth scopes — the SA's IAM roles control actual permissions.
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # ── Shielded instance config ─────────────────────────────────────────────
    shielded_instance_config {
      enable_secure_boot          = true  # Verifies OS boot chain.
      enable_integrity_monitoring = true  # Detects runtime integrity violations.
    }

    # ── Workload Identity on nodes ───────────────────────────────────────────
    workload_metadata_config {
      # GKE_METADATA: the metadata server is replaced by the Workload Identity proxy.
      # Pods can NOT accidentally reach the node's SA via the metadata server.
      mode = "GKE_METADATA"
    }

    # Node tag used by the master-webhooks firewall rule.
    tags = ["gke-${var.cluster_name}"]

    labels = merge(var.common_tags, {
      pool = var.node_pool_name
    })

    metadata = {
      # Disable the legacy metadata endpoint (prevents SSRF attacks against metadata).
      disable-legacy-endpoints = "true"
    }
  }
}
