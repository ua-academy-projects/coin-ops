terraform {
  required_version = ">= 1.5.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.7"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

# ==========================================
# Мережа
# ==========================================
resource "libvirt_network" "monero_net" {
  name      = "monero-net"
  mode      = "nat"
  domain    = "monero.local"
  addresses = ["10.10.10.0/24"]
  autostart = true

  dns {
    enabled    = true
    local_only = false

    hosts {
      hostname = "frontend"
      ip       = "10.10.10.11"
    }
    hosts {
      hostname = "backend"
      ip       = "10.10.10.12"
    }
    hosts {
      hostname = "db"
      ip       = "10.10.10.13"
    }
  }

  dhcp {
    enabled = false
  }
}

# ==========================================
# Базовий Alpine образ (спільний для всіх VM)
# ==========================================
resource "libvirt_volume" "alpine_base" {
  name   = "alpine-base.qcow2"
  pool   = var.storage_pool
  source = var.alpine_image_url
  format = "qcow2"
}

# ==========================================
# Cloud-init: спільна частина (SSH ключ, пакети)
# ==========================================
resource "libvirt_cloudinit_disk" "commoninit" {
  name      = "commoninit.iso"
  pool      = var.storage_pool
  user_data = data.template_file.user_data_common.rendered
}

data "template_file" "user_data_common" {
  template = file("${path.module}/cloud-init/common.yml")
  vars = {
    ssh_public_key  = var.ssh_public_key
    deploy_git_repo = var.deploy_git_repo
    deploy_branch   = var.deploy_branch
  }
}

# ==========================================
# VM1: Frontend (React + Nginx)
# ==========================================
resource "libvirt_volume" "frontend_disk" {
  name           = "frontend.qcow2"
  base_volume_id = libvirt_volume.alpine_base.id
  pool           = var.storage_pool
  size           = 1073741824 # 1 ГБ
  format         = "qcow2"
}

resource "libvirt_cloudinit_disk" "frontend_init" {
  name      = "frontend-init.iso"
  pool      = var.storage_pool
  user_data = data.template_file.user_data_frontend.rendered
}

data "template_file" "user_data_frontend" {
  template = file("${path.module}/cloud-init/frontend.yml")
  vars = {
    ssh_public_key  = var.ssh_public_key
    deploy_git_repo = var.deploy_git_repo
    deploy_branch   = var.deploy_branch
    backend_ip      = "10.10.10.12"
    hostname        = "frontend"
    static_ip       = "10.10.10.11"
    gateway         = "10.10.10.1"
  }
}

resource "libvirt_domain" "frontend" {
  name      = "monero-frontend"
  memory    = "128"
  vcpu      = 1
  autostart = true

  cloudinit = libvirt_cloudinit_disk.frontend_init.id

  cpu {
    mode = "host-passthrough"
  }

  network_interface {
    network_id     = libvirt_network.monero_net.id
    addresses      = ["10.10.10.11"]
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.frontend_disk.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
    autoport    = true
  }
}

# ==========================================
# VM2: Backend + Worker (FastAPI + Python)
# ==========================================
resource "libvirt_volume" "backend_disk" {
  name           = "backend.qcow2"
  base_volume_id = libvirt_volume.alpine_base.id
  pool           = var.storage_pool
  size           = 1073741824 # 1 ГБ
  format         = "qcow2"
}

resource "libvirt_cloudinit_disk" "backend_init" {
  name      = "backend-init.iso"
  pool      = var.storage_pool
  user_data = data.template_file.user_data_backend.rendered
}

data "template_file" "user_data_backend" {
  template = file("${path.module}/cloud-init/backend.yml")
  vars = {
    ssh_public_key  = var.ssh_public_key
    deploy_git_repo = var.deploy_git_repo
    deploy_branch   = var.deploy_branch
    db_ip           = "10.10.10.13"
    db_password     = var.db_password
    hostname        = "backend"
    static_ip       = "10.10.10.12"
    gateway         = "10.10.10.1"
    monero_rpc_host = var.monero_rpc_host
    monero_rpc_port = var.monero_rpc_port
  }
}

resource "libvirt_domain" "backend" {
  name      = "monero-backend"
  memory    = "256"
  vcpu      = 1
  autostart = true

  cloudinit = libvirt_cloudinit_disk.backend_init.id

  cpu {
    mode = "host-passthrough"
  }

  network_interface {
    network_id     = libvirt_network.monero_net.id
    addresses      = ["10.10.10.12"]
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.backend_disk.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
    autoport    = true
  }
}

# ==========================================
# VM3: Database (PostgreSQL)
# ==========================================
resource "libvirt_volume" "db_disk" {
  name           = "db.qcow2"
  base_volume_id = libvirt_volume.alpine_base.id
  pool           = var.storage_pool
  size           = 1073741824 # 1 ГБ
  format         = "qcow2"
}

resource "libvirt_cloudinit_disk" "db_init" {
  name      = "db-init.iso"
  pool      = var.storage_pool
  user_data = data.template_file.user_data_db.rendered
}

data "template_file" "user_data_db" {
  template = file("${path.module}/cloud-init/db.yml")
  vars = {
    ssh_public_key = var.ssh_public_key
    db_password    = var.db_password
    hostname       = "db"
    static_ip      = "10.10.10.13"
    gateway        = "10.10.10.1"
    backend_ip     = "10.10.10.12"
  }
}

resource "libvirt_domain" "database" {
  name      = "monero-database"
  memory    = "256"
  vcpu      = 1
  autostart = true

  cloudinit = libvirt_cloudinit_disk.db_init.id

  cpu {
    mode = "host-passthrough"
  }

  network_interface {
    network_id     = libvirt_network.monero_net.id
    addresses      = ["10.10.10.13"]
    wait_for_lease = true
  }

  disk {
    volume_id = libvirt_volume.db_disk.id
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
    autoport    = true
  }
}
