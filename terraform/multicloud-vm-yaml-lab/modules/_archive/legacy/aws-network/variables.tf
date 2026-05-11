variable "name_prefix" {
  type = string
}

variable "network" {
  type = object({
    name        = string
    subnet_name = string
    cidr        = string
  })
}

variable "availability_zone" {
  type = string
}