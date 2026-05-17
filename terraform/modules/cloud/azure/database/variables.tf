variable "project_name" {
  type        = string
  description = "Project name for resource naming."
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name for Azure database resources."
}

variable "location" {
  type        = string
  description = "Azure location for Azure database resources."
}

variable "virtual_network_id" {
  type        = string
  description = "Virtual network ID used for private DNS linking."
}

variable "subnet_id" {
  type        = string
  description = "Delegated subnet ID for Azure PostgreSQL Flexible Server."
}

variable "db_password" {
  type        = string
  description = "Database admin password."
  sensitive   = true
}

variable "db_name" {
  type        = string
  description = "Application database name."
}

variable "db_username" {
  type        = string
  description = "Database admin username."
}

variable "db_port" {
  type        = number
  description = "Database port."
  default     = 5432
}

variable "sku_name" {
  type        = string
  description = "Azure PostgreSQL Flexible Server SKU."
}

variable "storage_mb" {
  type        = number
  description = "Azure PostgreSQL Flexible Server storage size in MB."
}

variable "backup_retention_days" {
  type        = number
  description = "Azure PostgreSQL Flexible Server backup retention period."
}
