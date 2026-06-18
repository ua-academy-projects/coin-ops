resource "kubernetes_namespace" "this" {
  metadata {
    name = var.jenkins.namespace
  }
}

resource "kubernetes_secret" "admin" {
  metadata {
    name      = var.jenkins.admin_secret_name
    namespace = kubernetes_namespace.this.metadata[0].name
  }

  data = {
    jenkins-admin-user     = var.jenkins.admin_username
    jenkins-admin-password = var.jenkins.admin_password_placeholder
  }

  type = "Opaque"
}

resource "helm_release" "jenkins" {
  name       = var.jenkins.release_name
  repository = var.jenkins.chart_repository
  chart      = var.jenkins.chart_name
  namespace  = kubernetes_namespace.this.metadata[0].name

  values = [
    yamlencode({
      controller = {
        serviceType = var.jenkins.service_type
        admin = {
          createSecret   = false
          existingSecret = kubernetes_secret.admin.metadata[0].name
          userKey        = "jenkins-admin-user"
          passwordKey    = "jenkins-admin-password"
        }
      }
    })
  ]

  depends_on = [kubernetes_secret.admin]
}
