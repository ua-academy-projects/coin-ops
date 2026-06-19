variable "cert_manager" {
  type = object({
    namespace           = string
    release_name        = string
    chart_repository    = string
    chart_name          = string
    chart_version       = string
    cluster_issuer_name = string
    acme_server         = string
    ingress_class_name  = string
  })
}

variable "acme_email" {
  type = string
}
