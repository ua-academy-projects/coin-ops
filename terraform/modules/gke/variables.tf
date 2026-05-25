# =============================================================================
# modules/gke/variables.tf
# =============================================================================
# Input variable definitions for the GKE module.
# =============================================================================

variable "project_id" {
  description = "GCP Project ID in which the cluster is deployed."
  type        = string
}

variable "region" {
  description = "GCP region for the regional cluster (e.g. us-central1)."
  type        = string
}

variable "cluster_name" {
  description = "Name of the GKE cluster."
  type        = string
  default     = "coin-ops-cluster"
}

variable "network_name" {
  description = "The VPC network name to deploy the cluster into."
  type        = string
}

variable "subnet_name" {
  description = "The subnetwork name to deploy the cluster nodes into."
  type        = string
}

# Secondary ranges are required for VPC-native (alias IP) clusters.
variable "pods_range_name" {
  description = "Name of the secondary IP range for Pods (must be pre-created on the subnet)."
  type        = string
  default     = "pods"
}

variable "services_range_name" {
  description = "Name of the secondary IP range for Services (must be pre-created on the subnet)."
  type        = string
  default     = "services"
}

variable "master_ipv4_cidr_block" {
  description = "CIDR block for the private control-plane endpoint (must be /28)."
  type        = string
  default     = "172.16.0.0/28"
}

variable "master_authorized_networks" {
  description = "List of CIDR blocks allowed to reach the control plane API server."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "node_pool_name" {
  description = "Name of the custom node pool."
  type        = string
  default     = "main-pool"
}

variable "node_machine_type" {
  description = "Machine type for cluster nodes."
  type        = string
  default     = "e2-standard-4"
}

variable "node_disk_size_gb" {
  description = "Boot disk size in GB for each node."
  type        = number
  default     = 100
}

variable "node_disk_type" {
  description = "Boot disk type for nodes. pd-ssd is recommended for production."
  type        = string
  default     = "pd-ssd"
}

variable "initial_node_count" {
  description = "Initial number of nodes per zone in the node pool."
  type        = number
  default     = 1
}

variable "min_node_count" {
  description = "Minimum number of nodes per zone for cluster autoscaler."
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum number of nodes per zone for cluster autoscaler."
  type        = number
  default     = 5
}

variable "kubernetes_version" {
  description = "Minimum Kubernetes master version. 'latest' picks the highest available release."
  type        = string
  default     = "latest"
}

variable "release_channel" {
  description = "Release channel for auto-upgrades: RAPID, REGULAR, or STABLE."
  type        = string
  default     = "REGULAR"
}

variable "common_tags" {
  description = "Key/value labels applied to all resources."
  type        = map(string)
  default     = {}
}
