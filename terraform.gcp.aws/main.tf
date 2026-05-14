terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "coinops-terraform-state"
    key            = "coin-ops/terraform.gcp.aws/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "coinops-terraform-locks"
    encrypt        = true
  }




  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
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
  })

  ssh_key = "${local.config.ssh.user}:${file(pathexpand(local.config.ssh.public_key_path))}"
}

provider "google" {
  project = local.config.project.gcp.id
  region  = local.config.project.gcp.region
  zone    = local.config.project.gcp.zone
}

provider "aws" {
  region = local.config.project.aws.region
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
  count   = local.config.cloud == "gcp" ? 1 : 0
  source  = "./terraform/modules/gcp-infra"
  config  = local.config
  ssh_key = local.ssh_key
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
}
