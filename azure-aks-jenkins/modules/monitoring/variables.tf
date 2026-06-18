variable "resource_group_name" {
  type = string
}

variable "resource_group_id" {
  type = string
}

variable "location" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "app_namespace" {
  type = string
}

variable "workspace_name" {
  type = string
}

variable "action_group_name" {
  type = string
}

variable "action_group_short_name" {
  type = string
}

variable "alert_email" {
  type    = string
  default = null
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "cpu_alert_threshold" {
  type    = number
  default = 80
}

variable "cpu_alert_severity" {
  type    = number
  default = 3
}

variable "heartbeat_alert_severity" {
  type    = number
  default = 2
}

variable "heartbeat_window_minutes" {
  type    = number
  default = 10
}

variable "heartbeat_evaluation_frequency" {
  type    = string
  default = "PT5M"
}

variable "tags" {
  type    = map(string)
  default = {}
}
