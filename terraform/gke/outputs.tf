# =============================================================================
# gke/outputs.tf
# =============================================================================
# Useful values emitted after `terraform apply`.
# Sensitive outputs are marked sensitive = true to redact them from plan logs.
# =============================================================================

output "cluster_name" {
  description = "The name of the GKE cluster."
  value       = google_container_cluster.this.name
}

output "cluster_location" {
  description = "The region the cluster was created in."
  value       = google_container_cluster.this.location
}

output "cluster_endpoint" {
  description = "The IP address of the GKE control-plane API server."
  value       = google_container_cluster.this.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded public CA certificate of the cluster."
  value       = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "node_sa_email" {
  description = "Email of the least-privilege GKE node service account."
  value       = google_service_account.gke_node_sa.email
}

output "workload_identity_pool" {
  description = "Workload Identity pool string. Use when annotating K8s ServiceAccounts."
  value       = "${var.project_id}.svc.id.goog"
}

output "vpc_name" {
  description = "Name of the GKE VPC network."
  value       = google_compute_network.gke_vpc.name
}

output "subnet_name" {
  description = "Name of the primary GKE subnet."
  value       = google_compute_subnetwork.gke_subnet.name
}

# ─── Convenience helpers ──────────────────────────────────────────────────────

output "get_credentials_command" {
  description = "Run this command locally to configure kubectl after `terraform apply`."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.this.name} --region ${var.region} --project ${var.project_id}"
}

output "nat_ip" {
  description = "The auto-allocated external IPs used by Cloud NAT (may be empty until after first apply)."
  value       = google_compute_router_nat.gke_nat.nat_ips
}
