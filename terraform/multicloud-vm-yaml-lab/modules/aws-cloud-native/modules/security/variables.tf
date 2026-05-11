variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "firewall" {
  type = any
}

variable "app_port" {
  type = number
}
