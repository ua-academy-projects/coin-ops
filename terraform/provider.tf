terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "google" {
  project = local.general.project_id
  region  = local.config.locations[local.general.location].gcp.region
  zone    = local.config.locations[local.general.location].gcp.zones.primary
}

provider "aws" {
  region = local.config.locations[local.general.location].aws.region
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id                 = var.azure_subscription_id
  client_id                       = var.azure_client_id
  client_secret                   = var.azure_client_secret
  tenant_id                       = var.azure_tenant_id
  resource_provider_registrations = "none"
}

