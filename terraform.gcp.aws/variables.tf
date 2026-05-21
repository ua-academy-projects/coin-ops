variable "cloud" {
  type        = string
  description = "Target cloud provider: gcp, aws, or azure"

  validation {
    condition     = contains(["gcp", "aws", "azure"], lower(var.cloud))
    error_message = "cloud must be one of: gcp, aws, azure."
  }
}

variable "inventory_output_path" {
  type        = string
  description = "Where Terraform should write the generated Ansible inventory."
  default     = "../ansible/inventory.generated"
}

variable "db_password" {
  description = "Password for managed PostgreSQL (AWS RDS or GCP Cloud SQL)."
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_name" {
  type        = string
  description = "Cloudflare zone name, for example smolyakov-devops.pp.ua. Leave empty to disable DNS automation."
  default     = ""
}

variable "cloudflare_account_id" {
  type        = string
  description = "Optional Cloudflare account ID for disambiguating the zone lookup."
  default     = ""
}

variable "cloudflare_record_name" {
  type        = string
  description = "Cloudflare DNS record name inside the zone."
  default     = "app"
}

variable "cloudflare_proxied" {
  type        = bool
  description = "Whether the Cloudflare record should be proxied."
  default     = true
}

variable "cloudflare_enable_azure_record" {
  type        = bool
  description = "Create the Azure Cloudflare record only after the public IP strategy is stable."
  default     = false
}

variable "ssh_allowed_source_cidr" {
  type        = string
  description = "Optional override for ssh.allowed_source_cidr from config.yml."
  default     = ""
}
