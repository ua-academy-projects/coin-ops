resource "kubernetes_namespace" "dev" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "dev" {
  name             = var.release_name
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = var.chart_version
  namespace        = kubernetes_namespace.dev.metadata[0].name
  create_namespace = false

  values = [
    yamlencode({
      service = {
        type = "LoadBalancer"
      }
      ingressClass = {
        enabled        = true
        isDefaultClass = false
        name           = var.ingress_class_name
      }
      providers = {
        kubernetesIngress = {
          publishedService = {
            enabled = true
          }
        }
      }
      logs = {
        general = {
          level = "INFO"
        }
      }
    })
  ]
}
