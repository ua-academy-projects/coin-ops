variable "environment" {
  type        = string
  description = "Deployment environment name."
}

variable "location" {
  type        = string
  description = "Azure region."
}

variable "project_name" {
  type        = string
  description = "Human-readable project name."
}

variable "name_prefix" {
  type        = string
  description = "Prefix used in Azure resource naming."
}

variable "resource_group_name" {
  type        = string
  description = "Main resource group name."
}

variable "aks_name" {
  type        = string
  description = "AKS cluster name."
}

variable "acr_name" {
  type        = string
  description = "Azure Container Registry name."
}

variable "dns_prefix" {
  type        = string
  description = "AKS DNS prefix."
}

variable "kubernetes_version" {
  type        = string
  description = "AKS Kubernetes version."
}

variable "node_count" {
  type        = number
  description = "AKS default node count."
}

variable "node_vm_size" {
  type        = string
  description = "AKS node size."
}

variable "jenkins_namespace" {
  type        = string
  description = "Namespace for Jenkins."
  default     = "jenkins"
}

variable "app_namespace" {
  type        = string
  description = "Namespace for applications."
  default     = "apps"
}

variable "jenkins_admin_username" {
  type        = string
  description = "Jenkins admin username."
  default     = "admin"
}

variable "jenkins_admin_password" {
  type        = string
  description = "Optional Jenkins admin password override."
  sensitive   = true
  default     = null
}

variable "jenkins_storage_size" {
  type        = string
  description = "Persistent storage size for Jenkins."
  default     = "20Gi"
}

variable "jenkins_chart_version" {
  type        = string
  description = "Version of the Jenkins Helm chart."
  default     = "5.8.47"
}

variable "aks_subnet_cidr" {
  type        = string
  description = "CIDR for AKS subnet."
  default     = "10.30.0.0/23"
}

variable "app_subnet_cidr" {
  type        = string
  description = "CIDR for future application subnet."
  default     = "10.30.2.0/24"
}

variable "vnet_cidr" {
  type        = string
  description = "CIDR for the virtual network."
  default     = "10.30.0.0/16"
}

variable "tags" {
  type        = map(string)
  description = "Common Azure tags."
  default     = {}
}

