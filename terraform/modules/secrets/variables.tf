variable "cloud_provider" {
  description = "Target cloud platform: 'gcp' or 'aws'"
  type        = string
}

variable "region" {
  description = "Cloud region"
  type        = string
}

variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "db_username" {
  description = "Database username"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "db_host" {
  description = "Database host or IP address"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "rabbitmq_password" {
  description = "RabbitMQ password"
  type        = string
  sensitive   = true
}

variable "resource_group_name" {
  description = "Azure Resource Group Name (empty for AWS/GCP)"
  type        = string
  default     = ""
}
