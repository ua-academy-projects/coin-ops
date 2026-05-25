# =============================================================================
# modules/load_balancer/variables.tf
# =============================================================================

variable "cloud_provider" {
  description = "Cloud provider: 'gcp', 'aws', or 'azure'"
  type        = string

  validation {
    condition     = contains(["gcp", "aws", "azure"], var.cloud_provider)
    error_message = "cloud_provider must be 'gcp', 'aws', or 'azure'."
  }
}

variable "name" {
  description = "Name of the load balancer"
  type        = string
}

variable "region" {
  description = "Provider-specific region where the load balancer is deployed"
  type        = string
}

variable "vpc_id" {
  description = "VPC / Network ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
}

variable "subnet_ids" {
  description = "Map of subnet name -> subnet ID"
  type        = map(string)
}

variable "backends" {
  description = "Map of backend instances to attach to the LB"
  type = map(object({
    subnet_name = string
    port        = number
    zone        = string # Provider-specific zone
  }))
}

variable "instance_ids" {
  description = "Map of instance name -> instance ID (used for AWS target group attachments)"
  type        = map(string)
}

variable "instance_self_links" {
  description = "Map of instance name -> instance self_link (used for GCP instance groups)"
  type        = map(string)
}

variable "health_check" {
  description = "Health check configuration"
  type = object({
    protocol            = string
    port                = number
    path                = string
    interval_sec        = number
    timeout_sec         = number
    healthy_threshold   = number
    unhealthy_threshold = number
  })
}

variable "listeners" {
  description = "Map of listeners (e.g., http, https)"
  type = map(object({
    port     = number
    protocol = string
  }))
}

variable "gcp_project_id" {
  description = "GCP Project ID"
  type        = string
  default     = ""
}

variable "common_tags" {
  description = "Common tags/labels to apply to resources"
  type        = map(string)
  default     = {}
}

variable "domains" {
  description = "List of domain names for the SSL certificate"
  type        = list(string)
  default     = []
}

variable "ip_address" {
  description = "Static IP address for the load balancer forwarding rules"
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "Azure Resource Group Name (empty for AWS/GCP)"
  type        = string
  default     = ""
}
