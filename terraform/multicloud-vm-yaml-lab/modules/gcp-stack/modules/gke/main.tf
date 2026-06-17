locals {
  cluster_name = "${var.name_prefix}-gke"
  pods_range   = "${var.name_prefix}-gke-pods"
  svc_range    = "${var.name_prefix}-gke-svc"
}

resource "google_compute_subnetwork" "gke" {
  name                     = "${var.name_prefix}-gke-subnet"
  project                  = var.project_id
  region                   = var.region
  network                  = var.network_self_link
  ip_cidr_range            = var.gke.subnet_cidr
  private_ip_google_access = true

  secondary_ip_range {
    range_name    = local.pods_range
    ip_cidr_range = var.gke.pods_cidr
  }
  secondary_ip_range {
    range_name    = local.svc_range
    ip_cidr_range = var.gke.services_cidr
  }
}

resource "google_service_account" "nodes" {
  project      = var.project_id
  account_id   = "${replace(var.name_prefix, "-", "")}gkenode"
  display_name = "${var.name_prefix} GKE nodes"
}

# Nodes pull app images from Artifact Registry.
resource "google_project_iam_member" "nodes_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "main" {
  name     = local.cluster_name
  project  = var.project_id
  location = var.region

  network    = var.network_self_link
  subnetwork = google_compute_subnetwork.gke.self_link

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false

  release_channel {
    channel = var.gke.release_channel
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = local.pods_range
    services_secondary_range_name = local.svc_range
  }

  lifecycle {
    ignore_changes = [node_config]
  }
}

resource "google_container_node_pool" "primary" {
  name     = "${var.name_prefix}-pool"
  project  = var.project_id
  location = var.region
  cluster  = google_container_cluster.main.name

  autoscaling {
    min_node_count = var.gke.min_nodes
    max_node_count = var.gke.max_nodes
  }

  node_config {
    machine_type    = var.gke.node_machine_type
    disk_size_gb    = 30
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      lab = var.name_prefix
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
