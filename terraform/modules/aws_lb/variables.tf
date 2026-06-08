variable "config" {
  type = any
}

variable "vpc_id" {
  type = string
}

variable "public_subnet_id" {
  type = string
}

variable "public_subnet_b_id" {
  type = string
}

# Map of k3s instance IDs — all three nodes registered in Target Group
# Example: { "k3s-server-1" = "i-0abc123", "k3s-server-2" = "i-0def456" }
variable "k3s_instance_ids" {
  type = map(string)
}