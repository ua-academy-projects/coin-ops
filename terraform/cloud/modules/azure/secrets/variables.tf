variable "resource_group_name" {
  type = string
}

variable "key_vault_name" {
  type = string
}

variable "secrets" {
  type = map(object({
    secret_id = string
  }))
}

variable "secret_access" {
  type = map(object({
    identity        = optional(string)
    service_account = optional(string)
    secrets         = list(string)
  }))
  default = {}
}

variable "workloads" {
  type = map(object({
    instance_type   = string
    image_family    = string
    placement       = string
    subnet          = string
    tags            = list(string)
    disk_size_gb    = number
    public_ip       = bool
    can_ip_forward  = bool
    identity        = optional(string)
    service_account = optional(string)
  }))
  default = {}
}

variable "managed_identity_principal_ids" {
  type    = map(string)
  default = {}
}
