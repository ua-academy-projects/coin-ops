# =============================================================================
# modules/compute/variables.tf
# =============================================================================
# Cloud-agnostic compute variables using dictionary/map pattern.
# =============================================================================

variable "cloud_provider" {
  description = "Cloud provider: 'gcp', 'aws', or 'azure'"
  type        = string

  validation {
    condition     = contains(["gcp", "aws", "azure"], var.cloud_provider)
    error_message = "cloud_provider must be 'gcp', 'aws', or 'azure'."
  }
}

# ─── Instance Type Mapping ───────────────────────────────────────────────────
variable "instance_type_map" {
  description = "Mapping of logical sizes to provider-specific instance types"
  type = map(object({
    gcp   = string
    aws   = string
    azure = optional(string)
  }))
}

# ─── Image / AMI Mapping ────────────────────────────────────────────────────
variable "image_map" {
  description = "Mapping of OS names to provider-specific images"
  type = map(object({
    gcp   = string
    aws   = string
    azure = optional(string)
  }))
}

# ─── Disk Type Mapping ──────────────────────────────────────────────────────
variable "disk_type_map" {
  description = "Mapping of logical disk types to provider-specific types"
  type = map(object({
    gcp   = string
    aws   = string
    azure = optional(string)
  }))
}

# ─── Region / Zone Mapping ──────────────────────────────────────────────────
variable "zone_map" {
  description = "Mapping of logical zones to provider-specific zones"
  type = map(object({
    gcp   = string
    aws   = string
    azure = optional(string)
  }))
}

# ─── VM Definitions (cloud-agnostic) ────────────────────────────────────────
variable "vms" {
  description = "Cloud-agnostic VM definitions using logical names from mapping dictionaries"
  type = map(object({
    instance_size  = optional(string, "micro")
    zone           = optional(string, "us-central-a")
    os_image       = optional(string, "debian-12")
    disk_size_gb   = optional(number, 10)
    disk_type      = optional(string, "standard")
    subnet_name    = optional(string, "terraform-test-subnet")
    private_ip     = optional(string, null)
    public_ip      = optional(bool, false)
    tags           = optional(map(string), {})
    network_tags   = optional(list(string), [])
    startup_script = optional(string, "")
    spot           = optional(bool, false)
  }))
}

# ─── Network References ─────────────────────────────────────────────────────
variable "vpc_id" {
  description = "VPC / Network ID (from networking module)"
  type        = string
}

variable "subnet_ids" {
  description = "Map of subnet name → ID (from networking module)"
  type        = map(string)
}

variable "security_group_ids" {
  description = "AWS security group IDs (from networking module, empty list for GCP)"
  type        = list(string)
  default     = []
}

# ─── SSH Configuration ──────────────────────────────────────────────────────
variable "ssh_user" {
  description = "SSH username"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_key" {
  description = "SSH public key content"
  type        = string
  default     = ""
}

# ─── GCP-specific ───────────────────────────────────────────────────────────
variable "gcp_project_id" {
  description = "GCP project ID (required when cloud_provider = gcp)"
  type        = string
  default     = ""
}

# ─── Tags / Labels ──────────────────────────────────────────────────────────
variable "common_tags" {
  description = "Common tags/labels for all resources"
  type        = map(string)
  default     = {}
}

variable "use_packer_image" {
  description = "Whether to use Packer-built images instead of base images"
  type        = bool
  default     = false
}

variable "resource_group_name" {
  description = "Azure Resource Group Name (empty for AWS/GCP)"
  type        = string
  default     = ""
}

variable "region" {
  description = "Provider-specific region where resources are deployed"
  type        = string
  default     = ""
}
