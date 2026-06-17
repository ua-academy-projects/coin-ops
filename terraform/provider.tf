provider "aws" {
  region = local.config.region_map.aws
}

provider "google" {
  project = local.config.clouds.gcp.project_id
  region  = local.config.region_map.gcp
}

provider "azurerm" {
  features {}
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "helm" {
  kubernetes = {
    host = module.aks.host

    client_certificate     = base64decode(module.aks.client_certificate)
    client_key             = base64decode(module.aks.client_key)
    cluster_ca_certificate = base64decode(module.aks.cluster_ca_certificate)
  }
}