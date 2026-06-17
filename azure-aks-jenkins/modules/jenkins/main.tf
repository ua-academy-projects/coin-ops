resource "random_password" "admin" {
  length           = 24
  special          = true
  override_special = "!@#%^*-_=+"
}

locals {
  admin_password = coalesce(var.jenkins_admin_password, random_password.admin.result)
}

resource "kubernetes_namespace_v1" "jenkins" {
  metadata {
    name = var.jenkins_namespace
  }
}

resource "kubernetes_namespace_v1" "app" {
  metadata {
    name = var.app_namespace
  }
}

resource "kubernetes_secret_v1" "jenkins_admin" {
  metadata {
    name      = "jenkins-admin"
    namespace = kubernetes_namespace_v1.jenkins.metadata[0].name
  }

  data = {
    username = var.jenkins_admin_username
    password = local.admin_password
  }

  type = "Opaque"
}

locals {
  jenkins_service_account_name = "jenkins"
}

resource "kubernetes_role_v1" "app_deployer" {
  metadata {
    name      = "jenkins-app-deployer"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  rule {
    api_groups = [""]
    resources  = ["configmaps", "secrets", "services", "pods", "pods/log"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments", "replicasets", "statefulsets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding_v1" "app_deployer" {
  metadata {
    name      = "jenkins-app-deployer"
    namespace = kubernetes_namespace_v1.app.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = local.jenkins_service_account_name
    namespace = kubernetes_namespace_v1.jenkins.metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.app_deployer.metadata[0].name
  }
}

resource "helm_release" "jenkins" {
  name             = "jenkins"
  namespace        = kubernetes_namespace_v1.jenkins.metadata[0].name
  repository       = "https://charts.jenkins.io"
  chart            = "jenkins"
  version          = var.jenkins_chart_version
  create_namespace = false
  timeout          = 900
  atomic           = true

  values = [
    templatefile(var.jenkins_values_template_path, {
      jenkins_namespace     = var.jenkins_namespace
      app_namespace         = var.app_namespace
      admin_secret_name     = kubernetes_secret_v1.jenkins_admin.metadata[0].name
      service_account_name  = local.jenkins_service_account_name
      jenkins_storage_size  = var.jenkins_storage_size
      acr_login_server      = var.acr_login_server
      acr_username          = var.acr_username
      acr_password          = var.acr_password
      azure_subscription_id = var.azure_subscription_id
      azure_tenant_id       = var.azure_tenant_id
    })
  ]

  depends_on = [
    kubernetes_role_binding_v1.app_deployer,
  ]
}
