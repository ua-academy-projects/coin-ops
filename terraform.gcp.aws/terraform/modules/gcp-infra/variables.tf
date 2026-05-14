variable "config" {
  description = "Decoded infrastructure config."
  type        = any
}

variable "ssh_key" {
  description = "SSH metadata value in user:public-key format."
  type        = string
}
