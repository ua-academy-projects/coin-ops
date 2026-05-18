variable "project_name" {
  description = "Project name for naming resources"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
}

variable "network_id" {
  description = "The VPC network ID to attach the database to"
  type        = string
}

variable "db_password" {
  description = "Password for the database user"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "cognitor"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "cognitor"
}

variable "db_tier" {
  description = "CloudSQL machine tier"
  type        = string
  default     = "db-f1-micro"
}

variable "edition" {
  description = "Cloud SQL edition"
  type        = string
  default     = "ENTERPRISE"
}

variable "disk_type" {
  description = "CloudSQL disk type"
  type        = string
  default     = "PD_HDD"
}

variable "disk_size" {
  description = "CloudSQL disk size in GB"
  type        = number
  default     = 10
}
