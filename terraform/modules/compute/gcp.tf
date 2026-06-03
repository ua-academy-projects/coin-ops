# ═════════════════════════════════════════════════════════════════════════════
# GCP COMPUTE INSTANCES & IAM
# ═════════════════════════════════════════════════════════════════════════════

resource "google_service_account" "k3s_node_sa" {
  count        = var.cloud_provider == "gcp" ? 1 : 0
  account_id   = "coinops-k3s-node-sa"
  display_name = "K3s Node Service Account"
  project      = var.gcp_project_id
}

resource "google_project_iam_member" "k3s_node_secrets_accessor" {
  count   = var.cloud_provider == "gcp" ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.k3s_node_sa[0].email}"
}

data "google_compute_image" "packer" {
  count = (var.cloud_provider == "gcp" && var.use_packer_image) ? 1 : 0

  family  = "coinops"
  project = var.gcp_project_id
}

resource "google_compute_instance" "this" {
  for_each = var.cloud_provider == "gcp" ? local.resolved_vms : {}

  name         = each.key
  machine_type = each.value.instance_type
  zone         = each.value.zone
  project      = var.gcp_project_id

  boot_disk {
    initialize_params {
      image = var.use_packer_image ? data.google_compute_image.packer[0].self_link : each.value.image
      size  = each.value.disk_size_gb
      type  = each.value.disk_type
    }
  }

  network_interface {
    network    = var.vpc_id
    subnetwork = var.subnet_ids[each.value.subnet_name]
    network_ip = each.value.private_ip

    dynamic "access_config" {
      for_each = each.value.public_ip ? [1] : []
      content {}
    }
  }

  labels = merge(var.common_tags, each.value.tags)
  tags   = each.value.network_tags

  service_account {
    email  = google_service_account.k3s_node_sa[0].email
    scopes = ["cloud-platform"]
  }

  metadata = merge(
    local.ssh_key_metadata != "" ? { ssh-keys = local.ssh_key_metadata } : {},
    each.value.startup_script != "" ? { startup-script = each.value.startup_script } : {}
  )

  scheduling {
    preemptible                 = each.value.spot
    provisioning_model          = each.value.spot ? "SPOT" : "STANDARD"
    automatic_restart           = each.value.spot ? false : true
    instance_termination_action = each.value.spot ? "STOP" : null
  }

  lifecycle {
    ignore_changes = [boot_disk[0].initialize_params[0].image]
  }
}
