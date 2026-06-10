provider "aws" {
  region  = local.aws_region
  profile = try(local.config.clouds.aws.profile, null)
}

provider "google" {
  project = try(local.config.clouds.gcp.project_id, null)
  region  = local.gcp_region
  zone    = local.gcp_zone
}

provider "cloudflare" {}


provider "azurerm" {
  resource_provider_registrations = "none"
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
  }

  subscription_id = try(local.config.clouds.azure.subscription_id, "") != "" ? local.config.clouds.azure.subscription_id : null
  tenant_id       = try(local.config.clouds.azure.tenant_id, "") != "" ? local.config.clouds.azure.tenant_id : null
}
