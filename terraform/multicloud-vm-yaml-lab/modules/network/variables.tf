variable "region" {
  type = string
}

variable "network" {
  type = object({
    name        = string
    subnet_name = string
    cidr        = string
  })
}
