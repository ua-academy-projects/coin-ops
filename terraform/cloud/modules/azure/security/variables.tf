variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "subnet_ids" {
  type = map(string)
}

variable "subnets" {
  type = map(object({
    cidr      = string
    placement = string
    exposure  = string
  }))
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
}

variable "rules" {
  type = map(object({
    description      = string
    direction        = string
    priority         = number
    protocol         = string
    ports            = list(string)
    cidr_blocks      = list(string)
    source_workloads = list(string)
    target_workloads = list(string)
  }))
}
