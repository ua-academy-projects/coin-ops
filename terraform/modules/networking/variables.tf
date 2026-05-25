# =============================================================================
# modules/networking/variables.tf
# =============================================================================
# Cloud-agnostic networking variables using dictionary/map pattern.
# Provider-specific values are resolved via:
#   var.mapping[var.logical_name][var.cloud_provider]
# =============================================================================

variable "cloud_provider" {
  description = "Cloud provider: 'gcp', 'aws', or 'azure'"
  type        = string

  validation {
    condition     = contains(["gcp", "aws", "azure"], var.cloud_provider)
    error_message = "cloud_provider must be 'gcp', 'aws', or 'azure'."
  }
}

# ─── VPC ─────────────────────────────────────────────────────────────────────
variable "vpc_name" {
  description = "Name for the VPC / network"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC (AWS requires this; GCP ignores it)"
  type        = string
  default     = "10.0.0.0/16"
}

# ─── Region Mapping ──────────────────────────────────────────────────────────
variable "region_map" {
  description = "Mapping of logical region names to provider-specific regions"
  type = map(object({
    gcp   = string
    aws   = string
    azure = optional(string)
  }))
}

variable "region" {
  description = "Logical region name (key into region_map)"
  type        = string
}

# ─── Subnets ─────────────────────────────────────────────────────────────────
variable "subnets" {
  description = "Subnet definitions using cloud-agnostic fields + zone mapping"
  type = map(object({
    cidr   = string
    public = optional(bool, true)
    zone_map = object({
      gcp   = string
      aws   = string
      azure = optional(string)
    })
  }))
}

# ─── Firewall / Security Rules ──────────────────────────────────────────────
variable "firewall_rules" {
  description = "Cloud-agnostic firewall/security rules"
  type = map(object({
    description       = optional(string, "Managed by Terraform")
    direction         = optional(string, "ingress")
    action            = optional(string, "allow")
    protocol          = string
    port              = optional(number, 0)
    source_cidrs      = optional(list(string), [])
    destination_cidrs = optional(list(string), [])
    # For GCP: source_tags → target_tags; For AWS: source SG → target SG
    source_group = optional(string, "")
    target_group = optional(string, "")
  }))
  default = {}
}

# ─── Tags / Labels ──────────────────────────────────────────────────────────
variable "common_tags" {
  description = "Common tags/labels for all resources"
  type        = map(string)
  default     = {}
}
