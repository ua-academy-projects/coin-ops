# gcp_lb/variables.tf
# Variables for TCP Load Balancer pointing to all k3s nodes.
# Replaces old single-node (node-03) variables.

variable "config" {
  type = any
}

variable "network" {
  type        = string
  description = "VPC network name"
}

# List of k3s instance names — LB distributes traffic across all of them
variable "k3s_instance_names" {
  type        = list(string)
  description = "Names of all k3s server instances"
  default     = ["k3s-server-1", "k3s-server-2", "k3s-server-3"]
}

# Map of instance name → zone — needed to create per-zone instance groups
variable "k3s_instance_zones" {
  type        = map(string)
  description = "Map of k3s instance name to GCP zone"
  default = {
    "k3s-server-1" = "europe-central2-a"
    "k3s-server-2" = "europe-central2-a"
    "k3s-server-3" = "europe-central2-b"
  }
}