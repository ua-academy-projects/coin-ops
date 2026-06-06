variable "name_prefix" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "key_vault_name" {
  type = string
}

variable "tenant_id" {
  type = string
}

variable "object_id" {
  type = string
}

# Extra principals (e.g. the human operator running `lab.sh secrets push` and the
# ansible cloud_secrets reads via `az keyvault secret show`) that need data-plane
# access to the vault. Managed in Terraform so it survives re-applies.
variable "operator_object_ids" {
  type    = list(string)
  default = []
}

variable "api_domain" {
  type = string
}

variable "secrets" {
  type = any
}
