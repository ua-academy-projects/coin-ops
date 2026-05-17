provider "google" {
  project = local.general.providers.gcp.project_id
  region  = local.general.providers.gcp.region
  zone    = local.general.providers.gcp.zone
}

provider "aws" {
  region = local.general.providers.aws.region

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Environment = local.general.environment
    }
  }
}

provider "azurerm" {
  features {}

  subscription_id = local.general.providers.azure.subscription_id
}
