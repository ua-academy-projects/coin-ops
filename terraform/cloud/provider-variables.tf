# provider-variables.tf
# -> contains all cloud specific variables

variable "azure_resource_group_name" {
  type        = string
  default     = null
  description = "Azure resource group used by terraform/cloud. Generated into azure.auto.tfvars.json by bootstrap/azure-bootstrap.sh."
}

variable "azure_key_vault_name" {
  type        = string
  default     = null
  description = "Azure Key Vault used for platform secrets. Generated into azure.auto.tfvars.json by bootstrap/azure-bootstrap.sh."
}

variable "azure_location" {
  type        = string
  default     = null
  description = "Azure region used by terraform/cloud. Generated into azure.auto.tfvars.json by bootstrap/azure-bootstrap.sh."
}
