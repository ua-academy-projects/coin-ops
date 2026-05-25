packer {
  required_plugins {
    googlecompute = {
      version = ">= 1.1.4"
      source  = "github.com/hashicorp/googlecompute"
    }
    ansible = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "project_id" {
  type    = string
  default = ""
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

source "googlecompute" "coinops" {
  project_id          = var.project_id
  source_image_family = "ubuntu-2204-lts"
  region              = var.region
  zone                = var.zone
  image_name          = "coinops-v1-{{timestamp}}"
  image_family        = "coinops"
  ssh_username        = "packer"
}

build {
  name = "coinops-gcp"
  sources = [
    "source.googlecompute.coinops"
  ]

  provisioner "ansible" {
    playbook_file = "../ansible/provision.yml"
    user          = "packer"
    use_proxy     = false
    extra_arguments = [
      "--extra-vars", "ansible_sudo_pass=NONE",
      "--extra-vars", "RABBITMQ_PASSWORD=dummy",
      "--extra-vars", "DB_PASSWORD=dummy",
      "--extra-vars", "SSH_KEY_PATH=dummy",
      "--extra-vars", "RUNTIME_BACKEND=postgres"
    ]
  }
}
