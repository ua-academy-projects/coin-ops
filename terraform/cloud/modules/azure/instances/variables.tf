variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "ssh_public_key_path" {
  type = string
}

variable "subnet_ids" {
  type = map(string)
}

variable "application_security_group_ids" {
  type    = map(string)
  default = {}
}

variable "key_vault_name" {
  type = string
}

variable "workloads" {
  type = map(object({
    instance_type  = string
    image_family   = string
    placement      = string
    subnet         = string
    tags           = list(string)
    disk_size_gb   = number
    public_ip      = bool
    can_ip_forward = bool
    identity       = optional(string)
    secrets        = optional(list(string))
  }))
}
