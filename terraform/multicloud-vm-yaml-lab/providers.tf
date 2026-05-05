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
