# =============================================================================
# gke/versions.tf
# =============================================================================
# Terraform and provider version constraints for the GKE stack.
#
# Why a separate root module?
#   The existing terraform/ root manages VM-based infra across GCP/AWS/Azure.
#   GKE is a fundamentally different lifecycle (cluster vs. VMs), so it gets
#   its own root to allow independent plan/apply cycles and state file.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    # google-beta is needed for some GKE features (Dataplane V2, etc.)
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  # ── Remote backend ──────────────────────────────────────────────────────────
  # Use a separate prefix from the VM state so changes to the cluster
  # cannot accidentally destroy VM resources.
  #
  # Init command:
  #   terraform init \
  #     -backend-config="bucket=<YOUR_STATE_BUCKET>" \
  #     -backend-config="prefix=terraform/gke-state"
  # ────────────────────────────────────────────────────────────────────────────
  backend "gcs" {}
}
