terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "cloudflare" {
  api_token = trimspace(local.effective_cloudflare_api_token != "" ? local.effective_cloudflare_api_token : "placeholder_token")
}
