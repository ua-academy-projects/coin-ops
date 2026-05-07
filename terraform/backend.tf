terraform {
  backend "gcs" {
    bucket      = "devops-intern-penina-tf-state"
    prefix      = "terraform/multi-cloud"
    credentials = "../../Cloud_GCP/key.json"
  }
}