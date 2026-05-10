packer {
  required_plugins {
    googlecompute = {
      source  = "github.com/hashicorp/googlecompute"
      version = ">= 1.1.5"
    }
  }
}

variable "project_id" {
  type = string
}

variable "zone" {
  type    = string
  default = "europe-central2-a"
}

variable "machine_type" {
  type    = string
  default = "e2-small"
}

variable "ssh_username" {
  type    = string
  default = "packer"
}

variable "source_image_family" {
  type    = string
  default = "debian-12"
}

variable "source_image_project_id" {
  type    = string
  default = "debian-cloud"
}

variable "image_family" {
  type    = string
  default = "coinops-app-host"
}

source "googlecompute" "app_host" {
  project_id              = var.project_id
  zone                    = var.zone
  machine_type            = var.machine_type
  ssh_username            = var.ssh_username
  source_image_family     = var.source_image_family
  source_image_project_id = [var.source_image_project_id]
  image_family            = var.image_family
  image_name              = "${var.image_family}-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  image_description       = "coin-ops app-host golden image with common packages and Docker preinstalled"
}

build {
  name    = "gcp-app-host"
  sources = ["source.googlecompute.app_host"]

  provisioner "shell" {
    execute_command = "chmod +x '{{ .Path }}'; sudo -E '{{ .Path }}'"
    script = "../common/scripts/prepare-app-host.sh"
  }
}
