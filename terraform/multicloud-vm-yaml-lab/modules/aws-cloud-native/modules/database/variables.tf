variable "name_prefix" { type = string }
variable "runtime" { type = any }
variable "vpc_id" { type = string }
variable "private_subnet_ids" { type = map(string) }
variable "app_security_group_id" { type = string }
variable "db_password" {
  type      = string
  sensitive = true
}
