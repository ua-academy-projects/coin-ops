variable "name" {
    type = string
    description = "Name of the VM instance."
}
variable "machine_type" {
    type = string
    description = "Type of the VM instance."
}
variable "zone" {
    type = string
    description = "Zone where the VM instance will be created."
}
variable "os_image" {
    type = string
    description = "OS image for the VM instance."
}
variable "disk_size" {
    type = number
    description = "Size of the disk for the VM instance."
}
variable "vpc_name" {
    type = string
    description = "Name of the VPC network."
}
variable "subnet_name" {
    type = string
    description = "Name of the subnet for the VM instance."
}
variable "has_external_ip" {
    type = bool
    description = "Whether the VM instance has an external IP address."
}
variable "tags" {
    type = list(string)
    description = "List of tags for the VM instance."
}