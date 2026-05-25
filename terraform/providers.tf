# =============================================================================
# providers.tf
# =============================================================================
# Provider configurations for GCP and AWS.
# Both are declared; the inactive one is skipped via skip_* flags.
# =============================================================================

provider "google" {
  project = coalesce(var.gcp_project_id, "dummy-project")
  region  = local.is_gcp ? local.region : "us-central1"
}

provider "aws" {
  region = local.is_aws ? local.region : "us-east-1"

  # Skip AWS credential validation when running in GCP mode
  skip_credentials_validation = !local.is_aws
  skip_requesting_account_id  = !local.is_aws
  skip_metadata_api_check     = !local.is_aws
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
  resource_provider_registrations = local.is_azure ? "core" : "none"
}
