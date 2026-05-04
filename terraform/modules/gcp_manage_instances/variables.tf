variable "instances" {
  type        = any
  description = "Map of VM instances from config.json (keyed by VM name)."
  default     = {}

  # Validation for instances (at least one instance must be defined)
  validation {
    condition     = length(var.instances) > 0
    error_message = "At least one instance must be defined in 'instances'."
  }

  # Validation for instance names (must comply with GCP naming rules)
  validation {
    condition = alltrue([
      for name in keys(var.instances) : can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", name))
    ])
    error_message = "Instance names must comply with GCP naming rules: start with a lowercase letter, contain only lowercase letters, numbers, and hyphens, and be 2-63 characters long."
  }

  # Validation for disk_size (must be at least 10 GB, if provided)
  validation {
    condition = alltrue([
      for name, cfg in var.instances : !can(cfg.disk_size) || cfg.disk_size >= 10
    ])
    error_message = "disk_size in instances must be at least 10 GB (GCP minimum for boot disk)."
  }

  # Validation for zone (must be a valid GCP zone format, if provided)
  validation {
    condition = alltrue([
      for name, cfg in var.instances : !can(cfg.zone) || can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", cfg.zone))
    ])
    error_message = "zone in instances must be a valid GCP zone format (e.g. europe-central2-a)."
  }
}

variable "defaults" {
  type = object({
    zone            = optional(string, "europe-central2-a")
    machine_type    = optional(string, "e2-micro")
    os_image        = optional(string, "debian-cloud/debian-12")
    disk_size       = optional(number, 10)
    vpc_name        = optional(string, "default")
    subnet_name     = optional(string, "default")
    has_external_ip = optional(bool, false)
    tags            = optional(list(string), [])
  })
  default = {}

  # Validation for disk_size (must be at least 10 GB, if provided in defaults)
  validation {
    condition     = var.defaults.disk_size >= 10
    error_message = "disk_size in defaults must be at least 10 GB (GCP minimum for boot disk)."
  }

  # Validation for zone (must be a valid GCP zone format, if provided in defaults)
  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]-[a-z]$", var.defaults.zone))
    error_message = "zone in defaults must be a valid GCP zone format (e.g. europe-central2-a)."
  }
}
