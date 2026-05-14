variable "cloud" {
  description = "Selected cloud provider: gcp or aws."
  type        = string
}

variable "network_name" {
  description = "Network name used for cloud key names."
  type        = string
}

variable "ssh_user" {
  description = "SSH username."
  type        = string
}

variable "public_key_path" {
  description = "Path to SSH public key."
  type        = string
}
