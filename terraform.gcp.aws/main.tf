terraform {
  required_version = ">= 1.5.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}

locals {
  config_from_file = yamldecode(file("${path.module}/config.yml"))

  config = merge(local.config_from_file, {
    cloud = lower(var.cloud)
    ssh = merge(local.config_from_file.ssh, {
      allowed_source_cidr = var.ssh_allowed_source_cidr != "" ? var.ssh_allowed_source_cidr : local.config_from_file.ssh.allowed_source_cidr
    })
  })

  ssh_key = "${local.config.ssh.user}:${file(pathexpand(local.config.ssh.public_key_path))}"
}

provider "google" {
  project = local.config.project.gcp.id
  region  = local.config.project.gcp.region
  zone    = local.config.project.gcp.zone
}

provider "aws" {
  region                      = local.config.project.aws.region
  access_key                  = local.config.cloud == "aws" ? null : "mock_access_key"
  secret_key                  = local.config.cloud == "aws" ? null : "mock_secret_key"
  skip_credentials_validation = local.config.cloud != "aws"
  skip_region_validation      = local.config.cloud != "aws"
  skip_metadata_api_check     = local.config.cloud != "aws"
  skip_requesting_account_id  = local.config.cloud != "aws"
}

provider "azurerm" {
  features {}
  subscription_id = try(local.config.project.azure.subscription_id, null)
  tenant_id       = try(local.config.project.azure.tenant_id, null)
}

provider "cloudflare" {}

module "aws_infra" {
  count       = local.config.cloud == "aws" ? 1 : 0
  source      = "./terraform/modules/aws-infra"
  config      = local.config
  ssh_key     = local.ssh_key
  db_password = var.db_password
}

module "gcp_infra" {
  count       = local.config.cloud == "gcp" ? 1 : 0
  source      = "./terraform/modules/gcp-infra"
  config      = local.config
  ssh_key     = local.ssh_key
  db_password = var.db_password
}

module "azure_infra" {
  count       = local.config.cloud == "azure" ? 1 : 0
  source      = "./terraform/modules/azure-infra"
  config      = local.config
  ssh_key     = local.ssh_key
  db_password = var.db_password
}

module "cloudflare_dns" {
  count                 = var.cloudflare_zone_name != "" ? 1 : 0
  source                = "./terraform/modules/cloudflare-dns"
  cloud                 = local.config.cloud
  cloudflare_zone_name  = var.cloudflare_zone_name
  cloudflare_account_id = var.cloudflare_account_id
  record_name           = var.cloudflare_record_name
  proxied               = var.cloudflare_proxied
  aws_lb_dns_name       = local.config.cloud == "aws" ? module.aws_infra[0].load_balancer_dns_name : null
  gcp_lb_ip_address     = local.config.cloud == "gcp" ? module.gcp_infra[0].load_balancer_ip_address : null
  azure_lb_ip_address   = local.config.cloud == "azure" ? module.azure_infra[0].load_balancer_ip_address : null
  enable_azure_record   = var.cloudflare_enable_azure_record
}
