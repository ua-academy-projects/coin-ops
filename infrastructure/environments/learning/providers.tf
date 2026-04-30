provider "google" {
  project = local.general.project_id
  region  = local.general.region
  zone    = local.general.zone
}