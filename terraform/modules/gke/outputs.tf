# =============================================================================
# modules/gke/outputs.tf
# =============================================================================

output "cluster_name" {
  description = "The name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_endpoint" {
  description = "The private IP address of the cluster master."
  value       = google_container_cluster.this.endpoint
  sensitive   = true # IP of a private endpoint — keep out of plan logs.
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public certificate of the cluster CA."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "node_sa_email" {
  description = "Email of the GKE node service account."
  value       = google_service_account.gke_node_sa.email
}

output "workload_identity_pool" {
  description = "Workload Identity pool (used when binding K8s SAs to Google SAs)."
  value       = "${var.project_id}.svc.id.goog"
}

output "gke_subnet_name" {
  description = "Name of the subnet used by the GKE cluster."
  value       = google_compute_subnetwork.gke_subnet.name
}

# ─── kubectl helper ──────────────────────────────────────────────────────────
output "get_credentials_command" {
  description = "Run this command to configure kubectl after apply."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${var.region} --project ${var.project_id}"
}
