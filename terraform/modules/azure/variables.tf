variable "config" {
  type = any
}

variable "ssh_public_key" {
  type = string
}

variable "instances" {
  type    = any
  default = null
}