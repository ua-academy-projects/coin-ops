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
    chart-admin-username = var.jenkins.admin_username
    chart-admin-password = var.jenkins.admin_password_placeholder
  }

  type = "Opaque"
}

resource "kubernetes_service_account" "deployer" {
  metadata {
    name      = var.jenkins.jcasc.agent_service_account
    namespace = kubernetes_namespace.this.metadata[0].name
    annotations = {
      "azure.workload.identity/client-id" = var.workload_identity_client_id
      "azure.workload.identity/tenant-id" = var.workload_identity_tenant_id
    }
  }
}

resource "kubernetes_cluster_role_binding" "deployer" {
  metadata {
    name = "${var.jenkins.release_name}-deployer"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "cluster-admin"
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.deployer.metadata[0].name
    namespace = kubernetes_namespace.this.metadata[0].name
  }
}

resource "helm_release" "jenkins" {
  name       = var.jenkins.release_name
  repository = var.jenkins.chart_repository
  chart      = var.jenkins.chart_name
  namespace  = kubernetes_namespace.this.metadata[0].name

  values = [
    yamlencode(local.jenkins_values)
  ]

  depends_on = [
    kubernetes_cluster_role_binding.deployer,
    kubernetes_secret.admin
  ]
}
