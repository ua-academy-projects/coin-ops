variable "name" {
    type = string
}

variable "location" {
    type = string
}

variable "resource_group" {
  type = string
}

variable "vm_size" {
  type = string
}

variable "ssh_user" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "public_ip" {
  type = bool
  default = false
}

variable "private_ip" {
  type = string
}

variable "image" {
  type = string
}