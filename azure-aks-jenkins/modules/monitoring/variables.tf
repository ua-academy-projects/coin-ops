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

variable "tags" {
  type    = map(string)
  default = {}
}
