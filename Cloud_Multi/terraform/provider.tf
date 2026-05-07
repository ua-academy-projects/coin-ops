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
  }
}

provider "google" {
  credentials = file(var.gcp_credentials_file)
  project     = local.general.project_id
  region      = local.general.gcp_region
  zone        = local.general.gcp_zone
}

provider "aws" {
  region     = local.general.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}