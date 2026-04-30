# Remote state stored in GCS bucket.
# State is locked automatically during apply — prevents concurrent modifications.
terraform {
  backend "gcs" {
    bucket = "tfstate-project-8888321c-54a9-4dac-86d"
    prefix = "environments/learning"
  }
}