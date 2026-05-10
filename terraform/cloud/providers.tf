# providers.tf

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.31.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "6.44.0"
    }
  }
}

provider "google" {}

provider "aws" {}
