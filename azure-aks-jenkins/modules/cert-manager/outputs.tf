output "namespace" {
  value       = kubernetes_namespace.this.metadata[0].name
  description = "Namespace where cert-manager is installed."
}

output "cluster_issuer_name" {
  value       = var.cluster_issuer_name
  description = "ClusterIssuer used for application certificates."
}
