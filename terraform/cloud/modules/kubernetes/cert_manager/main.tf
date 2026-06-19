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

resource "kubernetes_manifest" "cluster_issuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = var.cert_manager.cluster_issuer_name
    }
    spec = {
      acme = {
        server = var.cert_manager.acme_server
        email  = var.acme_email
        privateKeySecretRef = {
          name = "${var.cert_manager.cluster_issuer_name}-account-key"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = var.cert_manager.ingress_class_name
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [helm_release.this]
}
