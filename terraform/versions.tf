# =============================================================================
# versions.tf
# =============================================================================
# Terraform version constraints and required providers.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # ── Remote Backend ──────────────────────────────────────────────────────────
  # Use partial configuration with -backend-config flags.
  #
  # GCP:  terraform init -backend-config="bucket=..." -backend-config="prefix=terraform/state"
  # AWS:  Comment out GCS backend, uncomment S3. Then:
  #       terraform init -backend-config="bucket=..." -backend-config="key=terraform/state"
  # ────────────────────────────────────────────────────────────────────────────

  # GCS Backend (for GCP deployments)
  backend "gcs" {}

  # S3 Backend (for AWS deployments) — uncomment and comment GCS above
  # backend "s3" {
  #   encrypt = true
  # }
}
