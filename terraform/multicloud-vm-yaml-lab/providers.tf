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

# --- Kubernetes + Helm: target the GKE cluster (gke-addons.tf installs Jenkins) --
# Their config depends on the cluster, so on a FIRST apply create the cluster first:
#   terraform apply -target=module.gcp
# then a normal `terraform apply` installs the addons. (try() keeps these inert on
# non-GCP applies / before the cluster exists.)
data "google_client_config" "current" {}

provider "kubernetes" {
  host                   = try("https://${module.gcp[0].gke_auth.endpoint}", "")
  token                  = data.google_client_config.current.access_token
  cluster_ca_certificate = try(base64decode(module.gcp[0].gke_auth.ca_certificate), "")
}

provider "helm" {
  kubernetes {
    host                   = try("https://${module.gcp[0].gke_auth.endpoint}", "")
    token                  = data.google_client_config.current.access_token
    cluster_ca_certificate = try(base64decode(module.gcp[0].gke_auth.ca_certificate), "")
  }
}
