variable "headlamp" {
  type = object({
    namespace            = string
    release_name         = string
    chart_repository     = string
    chart_name           = string
    chart_version        = optional(string)
    service_type         = string
    service_account_name = string
    cluster_role_name    = string
  })
}
