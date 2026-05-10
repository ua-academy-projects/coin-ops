packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = ">= 1.3.2"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "instance_type" {
  type    = string
  default = "t3.small"
}

variable "ssh_username" {
  type    = string
  default = "admin"
}

variable "source_ami_name_pattern" {
  type    = string
  default = "debian-12-amd64-*"
}

variable "source_ami_owner" {
  type    = string
  default = "136693071363"
}

variable "image_name_prefix" {
  type    = string
  default = "coinops-app-host"
}

source "amazon-ebs" "app_host" {
  region        = var.region
  instance_type = var.instance_type
  ssh_username  = var.ssh_username
  ami_name      = "${var.image_name_prefix}-${formatdate("YYYYMMDDhhmmss", timestamp())}"
  ami_description = "coin-ops app-host golden image with common packages and Docker preinstalled"

  source_ami_filter {
    filters = {
      name                = var.source_ami_name_pattern
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = [var.source_ami_owner]
    most_recent = true
  }

  tags = {
    Name    = var.image_name_prefix
    Project = "coin-ops"
    Role    = "app-host-image"
  }
}

build {
  name    = "aws-app-host"
  sources = ["source.amazon-ebs.app_host"]

  provisioner "shell" {
    execute_command = "chmod +x '{{ .Path }}'; sudo -E '{{ .Path }}'"
    script = "../common/scripts/prepare-app-host.sh"
  }
}
