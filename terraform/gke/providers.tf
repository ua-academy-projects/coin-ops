# =============================================================================
# gke/providers.tf
# =============================================================================
# Configure GCP providers for the GKE root module.
# =============================================================================

provider "google" {
  project = var.project_id
  region  = var.region
}

# google-beta is a superset of google and can manage the same resources.
# It is kept in sync with google but exposes in-preview APIs needed for
# some GKE features (e.g. Dataplane V2, advanced node config).
provider "google-beta" {
  project = var.project_id
  region  = var.region
}
