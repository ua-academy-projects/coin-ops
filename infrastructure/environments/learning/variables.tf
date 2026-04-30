variable "ssh_public_key" {
  description = "SSH public key content for VM access"
  type        = string
  sensitive   = true
}