output "cluster_name" {
  value = google_container_cluster.main.name
}

output "location" {
  value = google_container_cluster.main.location
}

output "endpoint" {
  value     = google_container_cluster.main.endpoint
  sensitive = true
}

output "ca_certificate" {
  value     = google_container_cluster.main.master_auth[0].cluster_ca_certificate
  sensitive = true
}

output "get_credentials_command" {
  value = "gcloud container clusters get-credentials ${google_container_cluster.main.name} --region ${var.region} --project ${var.project_id}"
}
