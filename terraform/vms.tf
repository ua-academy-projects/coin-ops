# ── Node 01: History (PostgreSQL + RabbitMQ + Python consumer + FastAPI) ──────

resource "null_resource" "clone_node01" {
  provisioner "local-exec" {
    command = <<-EOT
      $src = "${var.base_vhd_path}"
      $dst = "${var.vm_storage_path}\node-01\os.vhdx"
      New-Item -ItemType Directory -Force -Path "${var.vm_storage_path}\node-01"
      Copy-Item -Path $src -Destination $dst -Force
    EOT
    interpreter = ["powershell.exe", "-Command"]
  }
}

resource "null_resource" "seed_node01" {
  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      mkdir -p "${var.seed_staging_wsl_path}/node-01"
      cp "${path.module}/cloud-init/node-01/user-data"  "${var.seed_staging_wsl_path}/node-01/"
      cp "${path.module}/cloud-init/node-01/meta-data"  "${var.seed_staging_wsl_path}/node-01/"
      cp "${path.module}/cloud-init/node-01/network-config" "${var.seed_staging_wsl_path}/node-01/"
      sed -i "s|REPLACE_WITH_SSH_KEY|${var.ssh_public_key}|g" "${var.seed_staging_wsl_path}/node-01/user-data"
      genisoimage -output "${var.seed_staging_wsl_path}/node-01-seed.iso" \
        -volid cidata -joliet -rock \
        "${var.seed_staging_wsl_path}/node-01/user-data" \
        "${var.seed_staging_wsl_path}/node-01/meta-data" \
        "${var.seed_staging_wsl_path}/node-01/network-config"
    EOT
    interpreter = ["bash", "-c"]
  }
}

resource "hyperv_machine_instance" "node_history" {
  name                 = "softserve-node-01"
  generation           = 2
  memory_startup_bytes = var.vm_memory_mb * 1024 * 1024
  processor_count      = var.vm_processors
  dynamic_memory       = false

  network_adaptors {
    name        = "eth0"
    switch_name = hyperv_network_switch.internal.name
  }

  hard_disk_drives {
    path                = "${var.vm_storage_path}\\node-01\\os.vhdx"
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
  }

  dvd_drives {
    path                = "${var.seed_staging_windows_path}\\node-01-seed.iso"
    controller_number   = 0
    controller_location = 1
  }

  depends_on = [
    null_resource.clone_node01,
    null_resource.seed_node01,
  ]
}

# ── Node 02: Proxy (Go proxy + Redis) ────────────────────────────────────────

resource "null_resource" "clone_node02" {
  provisioner "local-exec" {
    command = <<-EOT
      $src = "${var.base_vhd_path}"
      $dst = "${var.vm_storage_path}\node-02\os.vhdx"
      New-Item -ItemType Directory -Force -Path "${var.vm_storage_path}\node-02"
      Copy-Item -Path $src -Destination $dst -Force
    EOT
    interpreter = ["powershell.exe", "-Command"]
  }
}

resource "null_resource" "seed_node02" {
  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      mkdir -p "${var.seed_staging_wsl_path}/node-02"
      cp "${path.module}/cloud-init/node-02/user-data"  "${var.seed_staging_wsl_path}/node-02/"
      cp "${path.module}/cloud-init/node-02/meta-data"  "${var.seed_staging_wsl_path}/node-02/"
      cp "${path.module}/cloud-init/node-02/network-config" "${var.seed_staging_wsl_path}/node-02/"
      sed -i "s|REPLACE_WITH_SSH_KEY|${var.ssh_public_key}|g" "${var.seed_staging_wsl_path}/node-02/user-data"
      genisoimage -output "${var.seed_staging_wsl_path}/node-02-seed.iso" \
        -volid cidata -joliet -rock \
        "${var.seed_staging_wsl_path}/node-02/user-data" \
        "${var.seed_staging_wsl_path}/node-02/meta-data" \
        "${var.seed_staging_wsl_path}/node-02/network-config"
    EOT
    interpreter = ["bash", "-c"]
  }
}

resource "hyperv_machine_instance" "node_proxy" {
  name                 = "softserve-node-02"
  generation           = 2
  memory_startup_bytes = var.vm_memory_mb * 1024 * 1024
  processor_count      = var.vm_processors
  dynamic_memory       = false

  network_adaptors {
    name        = "eth0"
    switch_name = hyperv_network_switch.internal.name
  }

  hard_disk_drives {
    path                = "${var.vm_storage_path}\\node-02\\os.vhdx"
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
  }

  dvd_drives {
    path                = "${var.seed_staging_windows_path}\\node-02-seed.iso"
    controller_number   = 0
    controller_location = 1
  }

  depends_on = [
    null_resource.clone_node02,
    null_resource.seed_node02,
  ]
}

# ── Node 03: UI (React + Nginx static serving) ────────────────────────────────

resource "null_resource" "clone_node03" {
  provisioner "local-exec" {
    command = <<-EOT
      $src = "${var.base_vhd_path}"
      $dst = "${var.vm_storage_path}\node-03\os.vhdx"
      New-Item -ItemType Directory -Force -Path "${var.vm_storage_path}\node-03"
      Copy-Item -Path $src -Destination $dst -Force
    EOT
    interpreter = ["powershell.exe", "-Command"]
  }
}

resource "null_resource" "seed_node03" {
  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      mkdir -p "${var.seed_staging_wsl_path}/node-03"
      cp "${path.module}/cloud-init/node-03/user-data"  "${var.seed_staging_wsl_path}/node-03/"
      cp "${path.module}/cloud-init/node-03/meta-data"  "${var.seed_staging_wsl_path}/node-03/"
      cp "${path.module}/cloud-init/node-03/network-config" "${var.seed_staging_wsl_path}/node-03/"
      sed -i "s|REPLACE_WITH_SSH_KEY|${var.ssh_public_key}|g" "${var.seed_staging_wsl_path}/node-03/user-data"
      genisoimage -output "${var.seed_staging_wsl_path}/node-03-seed.iso" \
        -volid cidata -joliet -rock \
        "${var.seed_staging_wsl_path}/node-03/user-data" \
        "${var.seed_staging_wsl_path}/node-03/meta-data" \
        "${var.seed_staging_wsl_path}/node-03/network-config"
    EOT
    interpreter = ["bash", "-c"]
  }
}

resource "hyperv_machine_instance" "node_ui" {
  name                 = "softserve-node-03"
  generation           = 2
  memory_startup_bytes = var.vm_memory_mb * 1024 * 1024
  processor_count      = var.vm_processors
  dynamic_memory       = false

  network_adaptors {
    name        = "eth0"
    switch_name = hyperv_network_switch.internal.name
  }

  hard_disk_drives {
    path                = "${var.vm_storage_path}\\node-03\\os.vhdx"
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
  }

  dvd_drives {
    path                = "${var.seed_staging_windows_path}\\node-03-seed.iso"
    controller_number   = 0
    controller_location = 1
  }

  depends_on = [
    null_resource.clone_node03,
    null_resource.seed_node03,
  ]
}
