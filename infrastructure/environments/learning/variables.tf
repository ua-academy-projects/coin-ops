variable "cloud" {
  description = "Target cloud provider (gcp, aws, or azure)"
  type        = string

  validation {
    condition     = contains(["gcp", "aws", "azure"], var.cloud)
    error_message = "Cloud must be one of: gcp, aws, azure."
  }
}

variable "ssh_public_key" {
  description = "SSH public key content for VM access"
  type        = string
  sensitive   = true
}

variable "app_domain" {
  description = "Public application domain for GCP HTTPS load balancer"
  type        = string
  default     = "coinops-kazachuk.pp.ua"
}

variable "cloud_sql_instance_name" {
  description = "Cloud SQL PostgreSQL instance name"
  type        = string
  default     = "coinops-postgres-learning"
}

variable "cloud_sql_database_name" {
  description = "Application database name in Cloud SQL"
  type        = string
  default     = "cognitor"
}

variable "db_secret_name" {
  description = "GCP Secret Manager secret name for grouped database secrets"
  type        = string
  default     = "coinops-db-secrets"
}

variable "service_secret_name" {
  description = "GCP Secret Manager secret name for grouped service secrets"
  type        = string
  default     = "coinops-service-secrets"
}
