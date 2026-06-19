# variables.tf

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "name" {
  type = string
}

variable "vm_ids" {
  type = map(string)
}

variable "aks_cluster_id" {
  type    = string
  default = null
}

variable "aks_monitoring_enabled" {
  type    = bool
  default = false
}

variable "aks_log_categories" {
  type = list(string)
  default = [
    "kube-apiserver",
    "kube-audit-admin",
    "kube-controller-manager",
    "kube-scheduler",
    "cluster-autoscaler"
  ]
}

variable "postgresql_server_id" {
  type    = string
  default = null
}

variable "postgresql_monitoring_enabled" {
  type    = bool
  default = false
}


# alerts

variable "vm_cpu_alert_enabled" {
  type    = bool
  default = true
}

variable "postgresql_cpu_alert_enabled" {
  type    = bool
  default = true
}

variable "postgresql_storage_alert_enabled" {
  type    = bool
  default = true
}

variable "postgresql_connections_alert_enabled" {
  type    = bool
  default = true
}

variable "postgresql_failed_connections_alert_enabled" {
  type    = bool
  default = true
}

# insights

variable "frontend_public_ip" {
  type    = string
  default = null
}

variable "http_availability_tests_enabled" {
  type    = bool
  default = false
}
