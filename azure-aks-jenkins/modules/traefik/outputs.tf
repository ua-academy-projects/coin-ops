output "namespace" {
  value       = kubernetes_namespace.this.metadata[0].name
  description = "Namespace where Traefik is installed."
}

output "release_name" {
  value       = helm_release.this.name
  description = "Traefik Helm release name."
}
