packer {
  required_plugins {
    amazon = {
      version = ">= 1.2.8"
      source  = "github.com/hashicorp/amazon"
    }
    ansible = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

source "amazon-ebs" "coinops" {
  ami_name      = "coinops-v1-{{timestamp}}"
  instance_type = "t3.micro"
  region        = var.region
  source_ami_filter {
    filters = {
      name                = "debian-12-amd64-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["136693071363"] # Debian
  }
  ssh_username = "admin"
}

build {
  name = "coinops-aws"
  sources = [
    "source.amazon-ebs.coinops"
  ]

  provisioner "ansible" {
    playbook_file = "../ansible/provision.yml"
    user          = "admin"
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
