# =============================================================================
# k3s/versions.tf
# =============================================================================
# Terraform version constraints and required providers for the k3s HA cluster.
#
# Provider overview:
#   hashicorp/google     – GCP infrastructure (VPC, Compute, LB, IAP, NAT)
#   hashicorp/helm       – Deploy Cilium, cert-manager, Headlamp add-ons
#   hashicorp/kubernetes – Apply any post-bootstrap K8s manifests
#   hashicorp/tls        – Generate ephemeral SSH key-pairs in Terraform state
#   hashicorp/time       – time_sleep to wait for the k3s API to become ready
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }

  # ── Remote Backend ──────────────────────────────────────────────────────────
  # Initialise with:
  #   terraform -chdir=k3s init \
  #     -backend-config="bucket=<YOUR_STATE_BUCKET>" \
  #     -backend-config="prefix=terraform/k3s"
  # ────────────────────────────────────────────────────────────────────────────
  backend "gcs" {}
}
