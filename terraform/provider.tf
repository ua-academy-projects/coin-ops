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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
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


provider "helm" {
  kubernetes {
    host                   = module.aws_eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.aws_eks.cluster_ca)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", module.aws_eks.cluster_name]
      command     = "aws"
    }
  }
}

provider "kubernetes" {
  host                   = module.aws_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.aws_eks.cluster_ca)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.aws_eks.cluster_name]
    command     = "aws"
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}
