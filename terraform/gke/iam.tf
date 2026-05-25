# =============================================================================
# gke/iam.tf
# =============================================================================
# Dedicated GKE node service account with least-privilege IAM roles.
#
# Production reasoning:
#   • The Compute Engine *default* SA has Editor on the whole project — never
#     use it for GKE nodes.
#   • Only the minimum roles for logging, monitoring, and image pulling are
#     granted here. Application-level GCP access is handled via Workload
#     Identity (individual Pod SAs), NOT by adding more roles here.
# =============================================================================

# ─── Node Service Account ─────────────────────────────────────────────────────
resource "google_service_account" "gke_node_sa" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-node-sa"
  display_name = "GKE Node SA — ${var.cluster_name}"
  description  = "Least-privilege SA for GKE worker nodes. Managed by Terraform."
}

# ─── IAM Bindings ─────────────────────────────────────────────────────────────
locals {
  # These are the ONLY roles a GKE node needs at the project level.
  node_sa_roles = toset([
    "roles/logging.logWriter",        # Ship container/node logs to Cloud Logging.
    "roles/monitoring.metricWriter",  # Push metrics to Cloud Monitoring.
    "roles/monitoring.viewer",        # Read cluster-level metrics.
    "roles/artifactregistry.reader",  # Pull images from Artifact Registry.
    "roles/storage.objectViewer",     # Pull images from Container Registry (legacy GCR).
  ])
}

resource "google_project_iam_member" "gke_node_sa_roles" {
  for_each = local.node_sa_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}
