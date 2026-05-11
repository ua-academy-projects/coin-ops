variable "name_prefix" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_ids" {
  type = map(string)
}

variable "lb_security_group_id" {
  type = string
}

variable "app_instance_ids" {
  type = map(string)
}

variable "app_port" {
  type = number
}

variable "health_path" {
  type = string
}
