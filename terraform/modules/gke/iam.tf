# =============================================================================
# modules/gke/iam.tf
# =============================================================================
# Dedicated least-privilege IAM Service Account for GKE nodes.
#
# Production reasoning:
#   • Nodes should NOT use the Compute Engine default SA, which carries broad
#     project-editor permissions. A scoped SA limits the blast radius if a node
#     is ever compromised.
#   • Workload Identity lets Pods assume dedicated GSAs via K8s SAs — far safer
#     than mounting service-account key files inside containers.
# =============================================================================

# ─── Node SA ─────────────────────────────────────────────────────────────────
resource "google_service_account" "gke_node_sa" {
  project      = var.project_id
  account_id   = "${var.cluster_name}-node-sa"
  display_name = "GKE Node SA — ${var.cluster_name}"
  description  = "Least-privilege SA for GKE worker nodes. Managed by Terraform."
}

# ─── Minimum IAM roles required for a GKE node ───────────────────────────────
# roles/logging.logWriter        — send container/node logs to Cloud Logging
# roles/monitoring.metricWriter  — push metrics to Cloud Monitoring
# roles/monitoring.viewer        — read cluster metrics
# roles/artifactregistry.reader  — pull images from Artifact Registry
# roles/storage.objectViewer     — pull images from GCR (legacy)
locals {
  node_sa_roles = [
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/artifactregistry.reader",
    "roles/storage.objectViewer",
  ]
}

resource "google_project_iam_member" "gke_node_sa_roles" {
  for_each = toset(local.node_sa_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.gke_node_sa.email}"
}
