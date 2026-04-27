terraform {
  backend "gcs" {
    bucket = "tfstate-project-8888321c-54a9-4dac-86d"
    prefix = "terraform/state"
  }
}
