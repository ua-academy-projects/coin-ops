variable "config" {
  type = any
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for marta_ops user"
}

variable "public_subnet_id" {
  type        = string
  description = "Public subnet ID zone a"
}

variable "public_subnet_b_id" {
  type        = string
  description = "Public subnet ID zone b"
}

variable "private_subnet_id" {
  type        = string
  description = "Private subnet ID zone a"
}

variable "private_subnet_b_id" {
  type        = string
  description = "Private subnet ID zone b"
}

variable "jump_host_nsg_id" {
  type        = string
  description = "NSG ID for jump host"
}

variable "internal_nsg_id" {
  type        = string
  description = "NSG ID for internal nodes"
}

variable "web_nsg_id" {
  type        = string
  description = "NSG ID for web node"
}