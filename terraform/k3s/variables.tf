# =============================================================================
# k3s/variables.tf
# =============================================================================
# Minimal variable surface.
#
# Almost all configuration is loaded from JSON files via locals.tf:
#   configs/cluster.json    — project, region, zones, helm versions
#   configs/networking.json — VPC, subnet CIDRs
#   configs/compute.json    — bastion + node definitions
#   configs/access.json     — IAP principals
#
# Secrets (k3s_token, SSH key) are stored in GCP Secret Manager and
# fetched at plan/apply time by secrets.tf — they are NEVER in tfvars or JSON.
#
# The only inputs left here are:
#   1. project_id  — override point for CI/CD (also in cluster.json as default)
#   2. environment — selects the configs/ sub-directory (future multi-env)
# =============================================================================

variable "project_id" {
  description = "GCP Project ID. Defaults to the value in configs/cluster.json. Override with TF_VAR_project_id in CI/CD."
  type        = string
  default     = "" # empty = use jsondecode'd value from cluster.json
}

variable "environment" {
  description = "Deployment environment (prod | staging | dev). Selects configs/environments/<env>/ if it exists."
  type        = string
  default     = "prod"
}
