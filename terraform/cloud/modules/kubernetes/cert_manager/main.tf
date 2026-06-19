resource "kubernetes_namespace" "this" {
  metadata {
    name = var.cert_manager.namespace
  }
}

resource "helm_release" "this" {
  name       = var.cert_manager.release_name
  repository = var.cert_manager.chart_repository
  chart      = var.cert_manager.chart_name
  version    = var.cert_manager.chart_version
  namespace  = kubernetes_namespace.this.metadata[0].name

  values = [
    yamlencode({
      crds = {
        enabled = true
      }
    })
  ]
}

resource "helm_release" "cluster_issuer" {
  name      = var.cert_manager.cluster_issuer_name
  chart     = "${path.module}/cluster_issuer"
  namespace = kubernetes_namespace.this.metadata[0].name

  # The issuer is installed with a small local chart so Helm waits until
  # cert-manager CRDs from the main release are available.
  values = [
    yamlencode({
      name         = var.cert_manager.cluster_issuer_name
      acmeServer   = var.cert_manager.acme_server
      acmeEmail    = var.acme_email
      ingressClass = var.cert_manager.ingress_class_name
    })
  ]

  depends_on = [helm_release.this]
}
