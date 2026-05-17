variable "name" {
    type = string
}

variable "resource_group" {
    type = string
}

variable "location" {
    type = string
}

variable "subnet_id" {
    type = string
}

variable "rules" {
    type = list(object({
        name = string
        priority = number
        direction = string
        access    = string
        protocol  = string
        port      = string
        source    = string

    }))
}