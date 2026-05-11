variable "name_prefix" { type = string }
variable "runtime" { type = any }
variable "project_id" { type = string }
variable "region" { type = string }
variable "network_self_link" { type = string }
variable "db_password" {
  type      = string
  sensitive = true
}
