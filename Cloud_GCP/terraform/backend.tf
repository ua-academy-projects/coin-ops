terraform {
  backend "gcs" {
    bucket      = "devops-intern-penina-tf-state"
    prefix      = "terraform/state"
    credentials = "../key.json"
  }
}