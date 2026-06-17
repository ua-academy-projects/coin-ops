variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "jenkins_namespace" {
  type = string
}

variable "app_namespace" {
  type = string
}

variable "jenkins_admin_username" {
  type = string
}

variable "jenkins_admin_password" {
  type      = string
  sensitive = true
  default   = null
}

variable "jenkins_storage_size" {
  type = string
}

variable "jenkins_chart_version" {
  type = string
}

variable "acr_login_server" {
  type = string
}

variable "acr_username" {
  type = string
}

variable "acr_password" {
  type      = string
  sensitive = true
}

variable "azure_subscription_id" {
  type = string
}

variable "azure_tenant_id" {
  type = string
}

variable "jenkins_values_template_path" {
  type = string
}

variable "depends_on_aks_ready_indicator" {
  type = string
}

