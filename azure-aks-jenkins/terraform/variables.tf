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

variable "ingress_controller_namespace" {
  type        = string
  description = "Namespace for the ingress controller."
  default     = "traefik"
}

variable "ingress_controller_release_name" {
  type        = string
  description = "Helm release name for the ingress controller."
  default     = "traefik"
}

variable "ingress_controller_chart_version" {
  type        = string
  description = "Version of the Traefik Helm chart."
  default     = "34.4.1"
}

variable "ingress_class_name" {
  type        = string
  description = "IngressClass name used by application ingresses."
  default     = "traefik"
}

variable "cert_manager_namespace" {
  type        = string
  description = "Namespace for cert-manager."
  default     = "cert-manager"
}

variable "cert_manager_release_name" {
  type        = string
  description = "Helm release name for cert-manager."
  default     = "cert-manager"
}

variable "cert_manager_chart_version" {
  type        = string
  description = "Version of the cert-manager Helm chart."
  default     = "v1.18.1"
}

variable "cluster_issuer_name" {
  type        = string
  description = "ClusterIssuer name used by ingress annotations."
  default     = "letsencrypt-prod"
}

variable "letsencrypt_email" {
  type        = string
  description = "Email used for Let's Encrypt ACME registration."
}

variable "alert_email" {
  type        = string
  description = "Email receiver used by Azure Monitor action group alerts."
  default     = null
}

variable "log_retention_days" {
  type        = number
  description = "Log Analytics retention period in days."
  default     = 30
}

variable "cpu_alert_threshold" {
  type        = number
  description = "Average AKS node CPU percentage threshold for alerts."
  default     = 80
}

variable "cpu_alert_severity" {
  type        = number
  description = "Severity used by high CPU and restart-related alerts."
  default     = 3
}

variable "heartbeat_alert_severity" {
  type        = number
  description = "Severity used by node/pod availability alerts."
  default     = 2
}

variable "heartbeat_window_minutes" {
  type        = number
  description = "Window size in minutes used by heartbeat-style alerts."
  default     = 10
}

variable "heartbeat_evaluation_frequency" {
  type        = string
  description = "Evaluation frequency used by heartbeat-style alerts."
  default     = "PT5M"
}

variable "monitoring_workspace_name" {
  type        = string
  description = "Log Analytics workspace name for AKS monitoring."
  default     = "azplat-dev-law"
}

variable "monitoring_action_group_name" {
  type        = string
  description = "Azure Monitor action group name."
  default     = "azplat-dev-ag"
}

variable "monitoring_action_group_short_name" {
  type        = string
  description = "Short name for the Azure Monitor action group."
  default     = "azpdevag"
}

variable "monitoring_identity_name" {
  type        = string
  description = "User-assigned managed identity for monitoring access."
  default     = "azplat-dev-monitoring-uami"
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
