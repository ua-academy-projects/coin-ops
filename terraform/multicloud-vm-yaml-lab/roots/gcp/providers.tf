provider "google" {
  project = local.raw.clouds.gcp.project_id
  region  = local.gcp_location.region
  zone    = local.gcp_location.zone
}
