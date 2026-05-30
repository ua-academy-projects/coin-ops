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
  backend "s3" {}
}

provider "google" {}

provider "aws" {}

provider "azurerm" {
  features {

  }
}
