variable "name_prefix" {
  type = string
}

variable "instances" {
  type = map(any)
}

variable "image_catalog" {
  type = map(any)
}

variable "ssh" {
  type = any
}

variable "ssh_public_key" {
  type = string
}

variable "app_names" {
  type = list(string)
}

variable "db_name" {
  type = string
}

variable "bastion_name" {
  type = string
}

variable "public_subnet_ids" {
  type = map(string)
}

variable "private_subnet_ids" {
  type = map(string)
}

variable "security_groups" {
  type = object({
    bastion = string
    lb      = string
    app     = string
    db      = string
  })
}


variable "create_db_instance" {
  type    = bool
  default = true
}

variable "app_iam_instance_profile_name" {
  type    = string
  default = null
}
