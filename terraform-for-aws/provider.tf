terraform {
  required_version = ">= 1.10.0"

  backend "s3" {
    bucket = "internship-state-bucket-1777712906"
    key    = "dev/terraform.tfstate"
    region = "eu-north-1"
    encrypt = true
    use_lockfile = true
  }
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = var.region
}