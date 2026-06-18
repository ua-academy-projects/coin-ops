# providers.tf

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.31.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "6.44.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.76.0"

    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.3"
    }
  }
  backend "azurerm" {}
}

provider "aws" {
  region                      = var.aws_region
  access_key                  = var.aws_access_key
  secret_key                  = var.aws_secret_key
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
}

provider "google" {

}

provider "azurerm" {
  features {

  }
}
