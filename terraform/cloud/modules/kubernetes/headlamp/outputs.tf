output "namespace" {
  value = kubernetes_namespace.this.metadata[0].name
}

output "release_name" {
  value = helm_release.this.name
}

output "status" {
  value = helm_release.this.status
}

output "service_account_name" {
  value = var.headlamp.service_account_name
}
