# =============================================================================
# k3s/bastion.tf
# =============================================================================
# Provisions the Bastion Host — the single secure SSH entry point.
#
# Security model:
#   - The Bastion has an ephemeral external IP so IAP can reach it.
#   - Direct TCP:22 from the internet is BLOCKED (no 0.0.0.0/0 firewall rule).
#   - SSH access is only possible through GCP Identity-Aware Proxy (IAP),
#     which requires authenticated, authorized Google Identity.
#   - An IAM binding grants the configured principals the
#     roles/iap.tunnelResourceAccessor role to enable IAP SSH.
#
# How to SSH through IAP (no keys needed if OS Login is configured):
#   gcloud compute ssh k3s-bastion \
#     --project=<PROJECT> --zone=<ZONE> \
#     --tunnel-through-iap
#
# How to multi-hop from Bastion to a k3s node:
#   gcloud compute ssh k3s-bastion \
#     --project=<PROJECT> --zone=<ZONE> \
#     --tunnel-through-iap \
#     -- -L 16443:<LB_IP>:6443 -N   # port-forward k3s API
#
# Or directly jump to a node:
#   gcloud compute ssh k3s-node-0 \
#     --project=<PROJECT> --zone=us-central1-a \
#     --tunnel-through-iap \
#     --internal-ip
# =============================================================================

# ─── SSH Key: now managed in secrets.tf (tls_private_key.k3s_ssh)
# ─────────────────────────────────────────────────────────────────────────────

# ─── Bastion Host Service Account ─────────────────────────────────────────────
resource "google_service_account" "bastion" {
  account_id   = "k3s-bastion-sa"
  display_name = "k3s Bastion Host Service Account"
  description  = "Minimal SA for the Bastion Host — logs and OS Login only"
}

# Allow the Bastion SA to write logs
resource "google_project_iam_member" "bastion_log_writer" {
  project = local.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.bastion.email}"
}

# ─── IAP Tunnel Access ────────────────────────────────────────────────────────
# Grant the listed principals the right to open IAP SSH tunnels to ANY VM
# in the project. Scope this down to a specific instance if required.
resource "google_project_iam_member" "iap_tunnel_access" {
  for_each = toset(local.iap_allowed_members)

  project = local.project_id
  role    = "roles/iap.tunnelResourceAccessor"
  member  = each.value
}

# ─── OS Login project-level (enables SSH via Google Identity) ─────────────────
resource "google_project_iam_member" "os_login" {
  for_each = toset(local.iap_allowed_members)

  project = local.project_id
  role    = "roles/compute.osLogin"
  member  = each.value
}

# ─── Bastion Host VM ──────────────────────────────────────────────────────────
resource "google_compute_instance" "bastion" {
  name         = "k3s-bastion"
  machine_type = local.bastion_machine_type
  zone         = local.zones[0] # place in the first zone
  tags         = ["bastion"]

  labels = {
    environment = local.cluster_cfg.environment
    role        = "bastion"
    managed_by  = "terraform"
  }

  boot_disk {
    initialize_params {
      image = local.bastion_image
      size  = 20
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.public.id

    # The Bastion has an external IP ONLY so that IAP can establish the tunnel.
    # Direct SSH (TCP:22) from the internet is blocked by firewall rules.
    access_config {}
  }

  service_account {
    email  = google_service_account.bastion.email
    scopes = ["cloud-platform"]
  }

  metadata = {
    # Enable OS Login — SSH keys are managed by IAM, not metadata
    enable-oslogin = "FALSE"

    # Public key sourced from Secret Manager (managed by secrets.tf)
    ssh-keys = "ubuntu:${google_secret_manager_secret_version.k3s_ssh_public_key.secret_data}"
  }

  # Minimal startup: harden SSH config, install gcloud components
  metadata_startup_script = <<-BASH
    #!/bin/bash
    set -euo pipefail

    # Harden SSH daemon
    sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    systemctl restart sshd

    # Install gcloud SDK if not present (Debian image usually has it)
    if ! command -v gcloud &>/dev/null; then
      apt-get update -qq && apt-get install -y google-cloud-sdk
    fi

    echo "Bastion host ready."
  BASH

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}
