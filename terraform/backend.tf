terraform {
  backend "gcs" {
    bucket = "internship-state-bucket"
    prefix = "infra/state"
  }
}