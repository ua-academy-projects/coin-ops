variable "config" {
  description = "Decoded infrastructure config."
  type        = any
}

variable "ssh_key" {
  description = "SSH metadata value in user:public-key format."
  type        = string
}

variable "db_password" {
  description = "Password for managed PostgreSQL in GCP Cloud SQL."
  type        = string
  sensitive   = true
}
