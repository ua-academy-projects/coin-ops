output "namespace" {
  value       = kubernetes_namespace.dev.metadata[0].name
  description = "Namespace where Traefik is installed."
}

output "release_name" {
  value       = helm_release.dev.name
  description = "Traefik Helm release name."
}
