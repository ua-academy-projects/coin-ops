
# terraform {
#   backend "gcs" {
#     bucket = "coinops-dev-tf-state"
#     prefix = "terraform/state/"
#   }
# }


terraform {
  backend "s3" {
    bucket  = "coinops-dev-tf-state"
    key     = "terraform/aws/state/default.tfstate"
    region  = "eu-central-1"
    encrypt = true
  }
}

# terraform {
#   backend "azurerm" {
#     resource_group_name = "devops-dev-rg"
#     storage_account_name = "coinopsdevtfstate"
#     container_name = "tfstate"
#     key = "terraform/azure/state/default.tfstate"
#   }
# }

#   terraform init -reconfigure
# DESTROY BEFORE CHANGING BACKGROUND