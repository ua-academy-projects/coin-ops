variable "name_prefix" {
  type = string
}

variable "network" {
  type = any
}

variable "public_subnets" {
  type = map(any)
}

variable "private_subnets" {
  type = map(any)
}
