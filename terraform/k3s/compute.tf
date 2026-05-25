# =============================================================================
# k3s/compute.tf
# =============================================================================
# Provisions 3 k3s control-plane VMs in the private subnet and configures
# them via cloud-init (user-data) to form a HA cluster with embedded etcd.
#
# Cycle-breaking strategy:
#   Both the LB VIP and node-0's private IP are pre-allocated as static
#   google_compute_address resources. This allows cloud-init templates to
#   reference concrete IPs without creating Terraform dependency cycles.
#
# Bootstrap sequence:
#   Node 0 (k3s_role=init):
#     k3s server --cluster-init --tls-san=<VIP> ...
#
#   Node 1 & 2 (k3s_role=server):
#     k3s server --server https://<NODE0_STATIC_IP>:6443 --tls-san=<VIP> ...
# =============================================================================

# ─── k3s Node Service Account ─────────────────────────────────────────────────
resource "google_service_account" "k3s_node" {
  account_id   = "k3s-node-sa"
  display_name = "k3s Node Service Account"
  description  = "SA for k3s control-plane nodes — logs, metrics, GCR, Secret Manager"
}

resource "google_project_iam_member" "k3s_node_log_writer" {
  project = local.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.k3s_node.email}"
}

resource "google_project_iam_member" "k3s_node_metric_writer" {
  project = local.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.k3s_node.email}"
}

resource "google_project_iam_member" "k3s_node_artifact_reader" {
  project = local.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.k3s_node.email}"
}

# ─── Pre-allocate static private IP for node-0 ───────────────────────────────
# Allocated BEFORE the VM exists so the join cloud-init template for nodes 1+
# can reference a concrete IP without creating a Terraform dependency cycle.
resource "google_compute_address" "k3s_node0_ip" {
  name         = "k3s-node-0-ip"
  region       = local.region
  address_type = "INTERNAL"
  subnetwork   = google_compute_subnetwork.private.id
  description  = "Static internal IP for k3s-node-0 (etcd cluster-init leader)"
}

# ─── Locals (cloud-init templates) ───────────────────────────────────────────

locals {
  # k3s token fetched from Secret Manager at plan time
  k3s_token = data.google_secret_manager_secret_version.k3s_token.secret_data

  # ── Node 0: cluster-init (etcd bootstrap leader) ──────────────────────────
  # References:
  #   google_compute_address.k3s_api_vip.address  — pre-allocated LB VIP
  #   (no instance references — no cycle)
  startup_script_init_node = <<-EOF
    #!/bin/bash
    # =========================================================================
    # k3s BOOTSTRAP — NODE 0 (cluster-init / etcd leader)
    # =========================================================================

    sleep 10

    export K3S_TOKEN="${local.k3s_token}"
    export INSTALL_K3S_VERSION="${local.k3s_version}"
    export INSTALL_K3S_EXEC="server \
      --cluster-init \
      --flannel-backend=none \
      --disable-network-policy \
      --disable=traefik \
      --disable=servicelb \
      --tls-san=${google_compute_address.k3s_api_vip.address} \
      --tls-san=k3s-node-0 \
      --node-ip=${google_compute_address.k3s_node0_ip.address} \
      --advertise-address=${google_compute_address.k3s_node0_ip.address} \
      --cluster-cidr=${local.pods_cidr} \
      --service-cidr=${local.services_cidr} \
      --write-kubeconfig-mode=644"
    
    curl -sfL https://get.k3s.io | sh -

    for i in \$(seq 1 60); do
      kubectl get nodes &>/dev/null && break
      echo "Waiting for k3s API... attempt \$i/60"
      sleep 5
    done

    kubectl label node \$(hostname) node-role.kubernetes.io/control-plane=true --overwrite
    kubectl label node \$(hostname) topology.kubernetes.io/zone=${local.zones[0]} --overwrite
    echo "k3s Node 0 (cluster-init) bootstrap complete."
  EOF

  # Template for Node 1 & 2 (join existing cluster as server peers).
  startup_script_join_node = <<-EOF
    #!/bin/bash
    # =========================================================================
    # k3s BOOTSTRAP — JOIN NODE (server peer / etcd voter)
    # =========================================================================

    sleep 45  # give node-0 time to fully bootstrap

    export K3S_TOKEN="${local.k3s_token}"
    export INSTALL_K3S_VERSION="${local.k3s_version}"
    export INSTALL_K3S_EXEC="server \
      --server https://${google_compute_address.k3s_node0_ip.address}:6443 \
      --flannel-backend=none \
      --disable-network-policy \
      --disable=traefik \
      --disable=servicelb \
      --tls-san=${google_compute_address.k3s_api_vip.address} \
      --node-ip=\$(hostname -I | awk '{print \$1}') \
      --advertise-address=\$(hostname -I | awk '{print \$1}') \
      --cluster-cidr=${local.pods_cidr} \
      --service-cidr=${local.services_cidr} \
      --write-kubeconfig-mode=644"
    
    curl -sfL https://get.k3s.io | sh -

    echo "k3s join node bootstrap complete."
  EOF
}

# ─── k3s Control-Plane Nodes ─────────────────────────────────────────────────

resource "google_compute_instance" "k3s_nodes" {
  count        = local.k3s_node_count
  name         = local.compute_cfg.nodes[count.index].name
  machine_type = local.mappings.instance_type_map[local.compute_cfg.nodes[count.index].instance_size]["gcp"]
  zone         = local.mappings.zone_map[local.compute_cfg.nodes[count.index].zone]["gcp"]
  tags         = local.compute_cfg.nodes[count.index].network_tags

  labels = merge(local.common_labels, {
    role       = "k3s-control-plane"
    node_index = tostring(count.index)
    k3s_role   = local.compute_cfg.nodes[count.index].k3s_role
  })

  boot_disk {
    initialize_params {
      image = local.mappings.image_map[local.compute_cfg.nodes[count.index].os_image]["gcp"]
      size  = local.compute_cfg.nodes[count.index].disk_size_gb
      type  = local.mappings.disk_type_map[local.compute_cfg.nodes[count.index].disk_type]["gcp"]
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.private.id

    # Node 0 gets its pre-allocated static IP; others get dynamic assignment
    network_ip = count.index == 0 ? google_compute_address.k3s_node0_ip.address : null
    # No access_config = no external IP
  }

  service_account {
    email  = google_service_account.k3s_node.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "FALSE"
    # SSH public key from Secret Manager
    ssh-keys = "ubuntu:${google_secret_manager_secret_version.k3s_ssh_public_key.secret_data}"

    # startup-script: init node gets cluster-init, join nodes get --server URL
    startup-script = local.compute_cfg.nodes[count.index].k3s_role == "init" ? local.startup_script_init_node : local.startup_script_join_node
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  depends_on = [
    google_compute_router_nat.nat,
    google_secret_manager_secret_version.k3s_ssh_public_key,
    google_compute_address.k3s_node0_ip,
    google_compute_address.k3s_api_vip,
  ]
}

# ─── Wait for cluster to be ready ─────────────────────────────────────────────
resource "time_sleep" "wait_for_k3s" {
  create_duration = "300s"
  depends_on      = [google_compute_instance.k3s_nodes]
}
