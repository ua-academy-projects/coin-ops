variable "config" {
  type = any
}
variable "network" {
  type        = string
  description = "VPC network name"
}
variable "ui_instance_name" {
  type        = string
  description = "Name of the UI instance (node-03)"
}
variable "ui_instance_zone" {
  type        = string
  description = "Zone of the UI instance"
}