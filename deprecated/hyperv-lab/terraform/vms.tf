locals {
  nodes = {
    "node-01" = { role = "history", mac = "00:15:5D:01:00:01" }
    "node-02" = { role = "proxy",   mac = "00:15:5D:01:00:02" }
    "node-03" = { role = "ui",      mac = "00:15:5D:01:00:03" }
  }
}

# Clone base VHDX for each node (runs on Windows via PowerShell)
resource "null_resource" "clone" {
  for_each = local.nodes

  provisioner "local-exec" {
    interpreter = ["powershell.exe", "-Command"]
    command     = <<-EOT
      New-Item -ItemType Directory -Force -Path "${var.vm_storage_path}\${each.key}"
      Copy-Item -Path "${var.base_vhd_path}" `
                -Destination "${var.vm_storage_path}\${each.key}\os.vhdx" `
                -Force
    EOT
  }
}

# Build cloud-init seed ISO for each node (runs in WSL)
resource "null_resource" "seed" {
  for_each = local.nodes

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      src="${path.module}/cloud-init/${each.key}"
      dst="${var.seed_staging_wsl_path}/${each.key}"
      mkdir -p "$dst"
      cp "$src/user-data" "$src/meta-data" "$src/network-config" "$dst/"
      sed -i "s|REPLACE_WITH_SSH_KEY|${var.ssh_public_key}|g" "$dst/user-data"
      sed -i "s|REPLACE_WITH_CONSOLE_PASSWORD|${var.vm_console_password}|g" "$dst/user-data"
      genisoimage \
        -output "${var.seed_staging_wsl_path}/${each.key}-seed.iso" \
        -volid cidata -joliet -rock \
        "$dst/user-data" "$dst/meta-data" "$dst/network-config"
    EOT
  }
}

# Create VMs — depends on both disk clone and seed ISO being ready
resource "hyperv_machine_instance" "node" {
  for_each = local.nodes

  name                 = "softserve-${each.key}"
  generation           = 2
  memory_startup_bytes = 1024 * 1024 * 1024 # 1024 MB startup
  memory_minimum_bytes = 512 * 1024 * 1024  # 512 MB minimum
  memory_maximum_bytes = var.vm_memory_mb * 1024 * 1024 # 2048 MB maximum (from variable)
  processor_count      = var.vm_processors
  dynamic_memory       = true

  vm_firmware {
    enable_secure_boot   = "On"
    secure_boot_template = "MicrosoftUEFICertificateAuthority"
  }

  network_adaptors {
    name               = "eth0"
    switch_name        = hyperv_network_switch.internal.name
    static_mac_address  = each.value.mac
    dynamic_mac_address = false
  }

  hard_disk_drives {
    path                = "${var.vm_storage_path}\\${each.key}\\os.vhdx"
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
  }

  dvd_drives {
    path                = "${var.seed_staging_windows_path}\\${each.key}-seed.iso"
    controller_number   = 0
    controller_location = 1
  }

  depends_on = [
    null_resource.clone,
    null_resource.seed,
  ]
}
