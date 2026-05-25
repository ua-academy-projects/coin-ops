# =============================================================================
# gke/variables.tf
# =============================================================================
# All tunable inputs for the GKE root module.
# Override values in gke.tfvars (or via -var flags in CI).
# =============================================================================

# ─── Project / Region ────────────────────────────────────────────────────────

variable "project_id" {
  description = "GCP Project ID."
  type        = string
}

variable "region" {
  description = "GCP region for the regional GKE cluster (e.g. us-central1)."
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Deployment environment label (dev | staging | prod)."
  type        = string
  default     = "prod"
}

# ─── Networking ──────────────────────────────────────────────────────────────

variable "vpc_name" {
  description = "Name for the new VPC network."
  type        = string
  default     = "coin-ops-gke-vpc"
}

variable "subnet_name" {
  description = "Name of the primary GKE subnet."
  type        = string
  default     = "coin-ops-gke-subnet"
}

variable "subnet_cidr" {
  description = "Primary CIDR for the GKE node subnet."
  type        = string
  default     = "10.0.0.0/20" # 4 k node IPs — enough for most clusters
}

variable "pods_cidr" {
  description = "Secondary CIDR for GKE Pod IP allocation."
  type        = string
  default     = "10.4.0.0/14" # ~256 k Pod IPs
}

variable "services_cidr" {
  description = "Secondary CIDR for GKE Service (ClusterIP) allocation."
  type        = string
  default     = "10.0.16.0/20" # 4 k ClusterIPs
}

variable "master_ipv4_cidr_block" {
  description = "CIDR for the private GKE control-plane (/28 required)."
  type        = string
  default     = "172.16.0.0/28"
}

variable "master_authorized_networks" {
  description = <<-EOT
    CIDRs allowed to reach the GKE control-plane API.
    Always include your CI/CD runner and VPN/bastion IPs.
    Never add 0.0.0.0/0 in production.
  EOT
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  # Example: replace with your actual VPN/bastion CIDR.
  default = [
    {
      cidr_block   = "10.0.0.0/8"
      display_name = "Internal RFC-1918"
    }
  ]
}

# ─── Cluster ─────────────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "Name of the GKE cluster."
  type        = string
  default     = "coin-ops-cluster"
}

variable "kubernetes_version" {
  description = "Minimum Kubernetes master version. 'latest' picks the highest available."
  type        = string
  default     = "latest"
}

variable "release_channel" {
  description = "GKE release channel: RAPID | REGULAR | STABLE."
  type        = string
  default     = "REGULAR"
}

# ─── Node Pool ───────────────────────────────────────────────────────────────

variable "node_pool_name" {
  description = "Name of the custom node pool."
  type        = string
  default     = "main-pool"
}

variable "node_machine_type" {
  description = "Compute instance type for GKE nodes."
  type        = string
  default     = "e2-standard-4" # 4 vCPU / 16 GB RAM — good all-purpose production size
}

variable "node_disk_size_gb" {
  description = "Boot disk size in GB per node."
  type        = number
  default     = 100
}

variable "node_disk_type" {
  description = "Boot disk type: pd-standard | pd-balanced | pd-ssd."
  type        = string
  default     = "pd-ssd" # SSD recommended for prod I/O
}

variable "initial_node_count" {
  description = "Initial number of nodes per zone."
  type        = number
  default     = 1
}

variable "min_node_count" {
  description = "Minimum nodes per zone (Cluster Autoscaler lower bound)."
  type        = number
  default     = 1
}

variable "max_node_count" {
  description = "Maximum nodes per zone (Cluster Autoscaler upper bound)."
  type        = number
  default     = 5
}
