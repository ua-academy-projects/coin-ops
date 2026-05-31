# variables.tf

variable "network" {
  type = object({
    name = string
    cidr = string
    subnets = map(object({
      cidr      = string
      placement = string
      exposure  = string
    }))
  })
}
