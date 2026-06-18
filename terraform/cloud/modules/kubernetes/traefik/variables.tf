variable "ingress_controller" {
  type = object({
    type               = string
    namespace          = string
    release_name       = string
    chart_repository   = string
    chart_name         = string
    chart_version      = optional(string)
    service_type       = string
    ingress_class_name = string
    default_class      = bool
  })
}
