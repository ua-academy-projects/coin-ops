# Використовуй GCS коли деплоїш на GCP
# terraform {
#   backend "gcs" {
#     bucket = "devops-intern-penina-tf-state"
#     prefix = "coinops-cloud/state"
#   }
# }

# Використовуй S3 коли деплоїш на AWS
terraform {
  backend "s3" {
    bucket = "devops-intern-penina-tf-state"
    key    = "coinops/terraform.tfstate"
    region = "eu-central-1"
  }
}