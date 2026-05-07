variable "cloud" {
  type = string
}

variable "vms" {
  type = any
}

variable "sizes" {
  type = any
}

variable "ami" {
  type = string
}

variable "default_disk" {
  type = number
}

variable "ops_user" {
  type = string
}

variable "ssh_port" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "public_subnet_id" {
  type = string
}

variable "private_subnet_id" {
  type = string
}

variable "jump_host_sg_id" {
  type = string
}

variable "internal_sg_id" {
  type = string
}