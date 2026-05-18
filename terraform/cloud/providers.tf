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
      version = "=4.1.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.5.3"
    }
  }
}

provider "google" {}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}

provider "azurerm" {
  features {}
}
