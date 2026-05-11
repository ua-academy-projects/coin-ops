variable "name_prefix" {
  type = string
}

variable "domain" {
  type = any
}

variable "lb_arn" {
  type = string
}

variable "lb_dns_name" {
  type = string
}

variable "target_group_arn" {
  type = string
}
