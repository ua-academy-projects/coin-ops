resource "kubernetes_namespace" "this" {
  metadata {
    name = var.ingress_controller.namespace
  }
}

resource "helm_release" "this" {
  name       = var.ingress_controller.release_name
  repository = var.ingress_controller.chart_repository
  chart      = var.ingress_controller.chart_name
  version    = try(var.ingress_controller.chart_version, null)
  namespace  = kubernetes_namespace.this.metadata[0].name

  values = [
    yamlencode({
      service = {
        type = var.ingress_controller.service_type
      }
      ingressClass = {
        enabled        = true
        isDefaultClass = var.ingress_controller.default_class
        name           = var.ingress_controller.ingress_class_name
      }
      providers = {
        kubernetesCRD = {
          enabled = true
        }
        kubernetesIngress = {
          enabled = true
        }
      }
    })
  ]
}
