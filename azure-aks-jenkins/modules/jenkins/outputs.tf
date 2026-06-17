output "jenkins_namespace" {
  value = kubernetes_namespace_v1.jenkins.metadata[0].name
}

output "app_namespace" {
  value = kubernetes_namespace_v1.app.metadata[0].name
}

output "admin_username" {
  value = var.jenkins_admin_username
}

output "admin_password" {
  value     = local.admin_password
  sensitive = true
}

output "service_name" {
  value = "jenkins"
}

