variable "name" {
  description = "Virtual Machine name"
  type        = string
}

variable "resource_group_name" {
  description = "Resource Group where the VM is created"
  type        = string
}

variable "location" {
  description = "Azure region"
  type        = string
}

variable "instance_type" {
  description = "Azure VM size (e.g. Standard_B1s)"
  type        = string
}

variable "os_image" {
  description = "OS image reference in publisher:offer:sku:version format"
  type        = string
}

variable "subnet_id" {
  description = "ID of the subnet the VM connects to"
  type        = string
}

variable "nsg_id" {
  description = "ID of the Network Security Group to attach to the NIC"
  type        = string
}

variable "ssh_user" {
  description = "Admin username for SSH access"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "SSH public key content"
  type        = string
}

variable "ssh_port" {
  description = "Custom SSH port configured via cloud-init"
  type        = number
  default     = 47832
}

variable "disk_size_gb" {
  description = "OS disk size in GB"
  type        = number
  default     = 30
}

variable "disk_type" {
  description = "OS disk storage type (Standard_LRS, StandardSSD_LRS, Premium_LRS)"
  type        = string
  default     = "Standard_LRS"
}

variable "assign_public_ip" {
  description = "Whether to create and attach a public IP"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all VM resources"
  type        = map(string)
  default     = {}
}
