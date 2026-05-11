variable "name_prefix" {
  type = string
}

variable "app_instances" {
  type = map(any)
}

variable "app_port" {
  type = number
}

variable "health_path" {
  type = string
}

variable "domain_enabled" {
  type = bool
}

variable "ip_address" {
  type = string
}

variable "certificate_self_link" {
  type = string
}
