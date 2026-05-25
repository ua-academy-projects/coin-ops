# =============================================================================
# gke/gke.tf
# =============================================================================
# GKE Regional Private Cluster + custom auto-scaling node pool.
#
# Production decisions at a glance:
# ┌─────────────────────────────┬───────────────────────────────────────────┐
# │ Feature                     │ Why                                       │
# ├─────────────────────────────┼───────────────────────────────────────────┤
# │ Regional cluster            │ Control plane + nodes span 3 zones → HA   │
# │ Private nodes               │ No public IPs on workers                  │
# │ Private endpoint (optional) │ Lock API server to internal network       │
# │ Authorized networks         │ Restrict kubectl access to known CIDRs    │
# │ Workload Identity           │ Pod-level GCP auth without key files      │
# │ Shielded nodes              │ Secure boot + integrity monitoring        │
# │ Dataplane V2 / eBPF         │ Better Network Policy, no kube-proxy      │
# │ GCE PD CSI driver           │ Stable dynamic PV provisioning            │
# │ Release channel: REGULAR    │ Managed, tested auto-upgrades             │
# │ Cluster Autoscaler          │ Right-size capacity automatically         │
# │ deletion_protection = true  │ Prevent accidental `terraform destroy`    │
# └─────────────────────────────┴───────────────────────────────────────────┘
# =============================================================================

resource "google_container_cluster" "this" {
  # google-beta exposes in-preview APIs used by Dataplane V2 and shielded nodes.
  provider = google-beta

  project  = var.project_id
  name     = var.cluster_name
  location = var.region # "region" = regional cluster (3 control-plane replicas)

  # ── Networking ──────────────────────────────────────────────────────────────
  network    = google_compute_network.gke_vpc.name
  subnetwork = google_compute_subnetwork.gke_subnet.name

  # VPC-native routing: Pod/Service IPs are alias IPs on the node NIC.
  # Required for Network Policy, Dataplane V2, and direct Pod routing.
  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # ── Private cluster ─────────────────────────────────────────────────────────
  private_cluster_config {
    enable_private_nodes = true # Nodes have no external IPs.

    # Keep the API server reachable via its external IP so developers and CI/CD
    # can run kubectl from outside the VPC (gated by authorized_networks below).
    # Set to true only if you have a bastion/VPN inside the VPC.
    enable_private_endpoint = false

    # /28 CIDR reserved exclusively for the GKE control-plane VMs (Google-managed).
    master_ipv4_cidr_block = var.master_ipv4_cidr_block
  }

  # ── Control-plane access ────────────────────────────────────────────────────
  # Only these CIDRs can reach the Kubernetes API server.
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # ── Kubernetes version / upgrades ───────────────────────────────────────────
  min_master_version = var.kubernetes_version

  release_channel {
    # REGULAR: production-tested releases roughly every 2 months.
    # Switch to STABLE for ultra-conservative environments.
    channel = var.release_channel
  }

  # ── Default node pool ───────────────────────────────────────────────────────
  # We immediately delete it so only our custom pool (below) exists.
  remove_default_node_pool = true
  initial_node_count       = 1 # Required by API; ignored after pool deletion.

  # ── Workload Identity ───────────────────────────────────────────────────────
  # Enables the GKE Workload Identity feature at the cluster level.
  # Individual namespaces/pods still need their own K8s SA ↔ Google SA binding.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # ── Add-ons ─────────────────────────────────────────────────────────────────
  addons_config {
    # HTTP LB add-on provisions GCP External HTTPS Load Balancers via Ingress.
    http_load_balancing {
      disabled = false
    }

    # Horizontal Pod Autoscaler (built into kube-controller-manager, enabled here).
    horizontal_pod_autoscaling {
      disabled = false
    }

    # GCE Persistent Disk CSI driver replaces the in-tree plugin.
    # Required for dynamic PVC provisioning with volume snapshots.
    gce_persistent_disk_csi_driver_config {
      enabled = true
    }

    # Node-local DNS cache reduces DNS query latency significantly.
    dns_cache_config {
      enabled = true
    }
  }

  # ── Dataplane V2 (eBPF) ─────────────────────────────────────────────────────
  # Replaces kube-proxy with eBPF programs. Required for fine-grained L4/L7
  # Network Policy and provides better observability.
  datapath_provider = "ADVANCED_DATAPATH"

  # ── Network Policy ──────────────────────────────────────────────────────────
  # Enables the NetworkPolicy API. With ADVANCED_DATAPATH the provider value is
  # ignored (eBPF enforces policies), but the block is required by the API.
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # ── Security ────────────────────────────────────────────────────────────────
  enable_shielded_nodes = true # Secure Boot + vTPM on every node.

  # ── Observability ───────────────────────────────────────────────────────────
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  # ── Maintenance policy ──────────────────────────────────────────────────────
  # Restrict auto-upgrades to weekend off-peak hours (UTC).
  # Adjust start/end to your traffic low point.
  maintenance_policy {
    recurring_window {
      start_time = "2024-01-01T02:00:00Z"
      end_time   = "2024-01-01T06:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=SA,SU"
    }
  }

  # ── Labels ──────────────────────────────────────────────────────────────────
  resource_labels = {
    environment  = var.environment
    managed_by   = "terraform"
    cluster_name = var.cluster_name
  }

  # ── Deletion protection ─────────────────────────────────────────────────────
  # Prevents `terraform destroy` from deleting a running production cluster.
  # Set to false in a .tfvars override when you intentionally want to destroy.
  deletion_protection = true

  lifecycle {
    ignore_changes = [
      # GKE normalises initial_node_count after pool creation.
      initial_node_count,
      # Allow GKE to increment the version through the release channel.
      min_master_version,
    ]
  }

  depends_on = [
    google_compute_subnetwork.gke_subnet,
    google_compute_router_nat.gke_nat,
  ]
}

# =============================================================================
# Custom Node Pool
# =============================================================================
resource "google_container_node_pool" "main" {
  provider = google-beta

  project  = var.project_id
  name     = var.node_pool_name
  cluster  = google_container_cluster.this.name
  location = var.region # Regional pool — nodes spread evenly across all zones.

  # ── Cluster Autoscaler ──────────────────────────────────────────────────────
  # min/max are *per zone*. A 3-zone regional pool with max_node_count=5 can
  # scale up to 15 nodes total.
  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  initial_node_count = var.initial_node_count

  # ── Rolling upgrade strategy ────────────────────────────────────────────────
  # Surge upgrades add one extra node before removing an old one, keeping
  # cluster capacity constant during upgrades.
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  # ── Node management ─────────────────────────────────────────────────────────
  management {
    auto_repair  = true # GKE automatically replaces broken nodes.
    auto_upgrade = true # GKE keeps node kubelet in sync with the control-plane channel.
  }

  node_config {
    machine_type = var.node_machine_type # e2-standard-4 = 4 vCPU / 16 GB RAM
    disk_size_gb = var.node_disk_size_gb
    disk_type    = var.node_disk_type    # pd-ssd for prod I/O performance

    # Use the least-privilege SA defined in iam.tf.
    service_account = google_service_account.gke_node_sa.email

    # cloud-platform scope + IAM roles (not primitive editor/viewer scopes).
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # ── Shielded instance ──────────────────────────────────────────────────────
    shielded_instance_config {
      enable_secure_boot          = true # Verifies UEFI firmware → bootloader → OS.
      enable_integrity_monitoring = true # Detects runtime OS integrity violations.
    }

    # ── Workload Identity on the node ──────────────────────────────────────────
    # GKE_METADATA: the instance metadata server is replaced by a proxy that
    # issues OIDC tokens for Pods — Pods cannot impersonate the node SA.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Network tag used by the master-webhooks firewall rule.
    tags = ["gke-${var.cluster_name}"]

    labels = {
      environment = var.environment
      managed_by  = "terraform"
      pool        = var.node_pool_name
    }

    metadata = {
      # Block the legacy v1beta1 metadata API (prevents container metadata SSRF).
      disable-legacy-endpoints = "true"
    }
  }
}
