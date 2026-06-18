resource "kubernetes_namespace" "dev" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "dev" {
  name             = var.release_name
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.chart_version
  namespace        = kubernetes_namespace.dev.metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      crds = {
        enabled = true
      }
      prometheus = {
        enabled = false
      }
    })
  ]
}

moved {
  from = kubernetes_namespace.this
  to   = kubernetes_namespace.dev
}

moved {
  from = helm_release.this
  to   = helm_release.dev
}
