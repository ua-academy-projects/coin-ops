# ============================================================
# BACKEND CONFIGURATION
# Comment out the one you are NOT using before terraform init
# ============================================================

# --- AWS Backend (use when cloud = "aws") ---
terraform {
  backend "s3" {
    bucket         = "devops-intern-penina-tf-state"
    key            = "coinops/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-state-lock"
  }
}

# --- GCP Backend (use when cloud = "gcp") ---
# terraform {
#   backend "gcs" {
#     bucket = "devops-intern-penina-tf-state"
#     prefix = "coinops-cloud/state"
#   }
# }

# --- Azure Backend (use when cloud = "azure") ---
# terraform {
#   backend "azurerm" {
#     resource_group_name  = "coinops-rg"
#     storage_account_name = "coinopspenina"
#     container_name       = "tfstate"
#     key                  = "coinops/terraform.tfstate"
#   }
# }