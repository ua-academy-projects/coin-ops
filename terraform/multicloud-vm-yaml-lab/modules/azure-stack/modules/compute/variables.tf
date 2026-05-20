variable "name_prefix" {
  type = string
}

variable "instances" {
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
  type = any
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}
