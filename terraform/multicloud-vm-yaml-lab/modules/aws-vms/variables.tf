variable "subnet_id" {
  type = string
}

variable "availability_zone" {
  type = string
}

variable "instances" {
  type = map(object({
    name          = string
    role          = string
    private_ip    = string
    public_ip     = bool
    tags          = list(string)
    instance_type = string
    image_key     = string
    disk_size_gb  = number
  }))
}

variable "image_catalog" {
  type = map(object({
    owners      = list(string)
    name_filter = string
  }))
}

variable "ssh_public_key_path" {
  type = string
}

variable "security_groups" {
  type = object({
    bastion = string
    private = string
  })
}