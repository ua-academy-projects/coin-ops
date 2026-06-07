# provider-variables.tf
# -> contains all cloud specific variables

variable "azure_resource_group_name" {
  type    = string
  default = null
}

variable "azure_key_vault_name" {
  type    = string
  default = null
}

variable "azure_location" {
  type    = string
  default = null
}
