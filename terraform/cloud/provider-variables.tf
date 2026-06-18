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

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for AWS runs. Azure runs use the default dummy value so the AWS provider does not block Azure planning."
}

variable "aws_access_key" {
  type        = string
  default     = "unused"
  sensitive   = true
  description = "AWS access key for AWS runs. Azure runs use the default dummy value."
}

variable "aws_secret_key" {
  type        = string
  default     = "unused"
  sensitive   = true
  description = "AWS secret key for AWS runs. Azure runs use the default dummy value."
}
