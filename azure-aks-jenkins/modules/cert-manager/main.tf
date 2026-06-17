resource "kubernetes_namespace" "this" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "this" {
  name             = var.release_name
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = var.chart_version
  namespace        = kubernetes_namespace.this.metadata[0].name
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
