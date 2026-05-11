variable "db_password" {
  description = "Managed PostgreSQL password. Set via TF_VAR_db_password, usually exported from DB_PASSWORD by scripts/lab.sh."
  type        = string
  sensitive   = true
  default     = null
}
