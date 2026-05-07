variable "cloud" {
  type = string
}

variable "vms" {
  type = any
}

variable "sizes" {
  type = any
}

variable "zone" {
  type = string
}

variable "image" {
  type = string
}

variable "default_disk" {
  type = number
}

variable "subnetwork" {
  type = string
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