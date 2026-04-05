terraform {
  required_version = ">= 1.5"

  required_providers {
    hyperv = {
      source  = "taliesins/hyperv"
      version = "~> 1.0"
    }
  }
}

# NOTE: WinRM runs over unencrypted HTTP (port 5985).
# This is acceptable for WSL-to-localhost connections only.
# If connecting to a remote Hyper-V host, switch to HTTPS (https = true, port = 5986).
provider "hyperv" {
  user     = var.winrm_user
  password = var.winrm_password
  host     = var.winrm_host
  port     = 5985
  https    = false
  insecure = true
  use_ntlm = true
  timeout  = "30s"
}
