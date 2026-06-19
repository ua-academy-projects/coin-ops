resource "kubernetes_namespace" "this" {
  metadata {
    name = var.headlamp.namespace
  }
}

resource "helm_release" "this" {
  name       = var.headlamp.release_name
  repository = var.headlamp.chart_repository
  chart      = var.headlamp.chart_name
  version    = try(var.headlamp.chart_version, null)
  namespace  = kubernetes_namespace.this.metadata[0].name

  values = [
    yamlencode({
      service = {
        type = var.headlamp.service_type
      }
      serviceAccount = {
        create = true
        name   = var.headlamp.service_account_name
      }
      clusterRoleBinding = {
        create          = true
        clusterRoleName = var.headlamp.cluster_role_name
      }
      config = {
        inCluster = true
      }
      ingress = {
        enabled = false
      }
    })
  ]
}
