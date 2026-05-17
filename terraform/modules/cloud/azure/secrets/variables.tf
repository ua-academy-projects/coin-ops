variable "resource_group_name" {
  type        = string
  description = "Resource group name for Azure Key Vault resources."
}

variable "location" {
  type        = string
  description = "Azure location for Azure Key Vault resources."
}

variable "tenant_id" {
  type        = string
  description = "Azure tenant ID used by Key Vault."
}

variable "key_vault_name" {
  type        = string
  description = "Deterministic Key Vault name used across Terraform and Ansible."
}

variable "db_secret_name" {
  type        = string
  description = "Logical secret name for DB secrets."
}

variable "app_secret_name" {
  type        = string
  description = "Logical secret name for app secrets."
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "rabbitmq_password" {
  type      = string
  sensitive = true
}

variable "ghcr_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}
