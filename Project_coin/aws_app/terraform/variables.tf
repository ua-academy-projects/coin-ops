variable "region" {
  default = "eu-central-1"

}
variable "ami" {
  description = "Ubuntu AMI"

}
variable "instance_type" {
  default = "t2.small"

}
variable "key_name" {
  description = "SSH key name"

}
