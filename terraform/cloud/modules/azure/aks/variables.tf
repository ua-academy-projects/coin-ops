variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "subnet_ids" {
  type = map(string)
}

variable "cluster" {
  type = object({
    name               = string
    dns_prefix         = string
    kubernetes_version = string
    subnet             = string
    sku_tier           = optional(string, "Free")
    node_pool = object({
      name            = string
      vm_size         = string
      node_count      = number
      os_disk_size_gb = number
    })
  })
}
