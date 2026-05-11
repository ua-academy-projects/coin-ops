locals {
  app_instance_networks = {
    for idx, name in var.app_names : name => {
      zone       = var.zones[idx % length(var.zones)]
      subnetwork = var.private_subnet_self_links[tostring(idx % length(var.private_subnet_self_links))]
    }
  }

  instance_networks = merge(
    {
      (var.bastion_name) = {
        zone       = var.zones[0]
        subnetwork = var.public_subnet_self_links["0"]
      }
    },
    local.app_instance_networks,
    {
      (var.db_name) = {
        zone       = var.zones[0]
        subnetwork = var.private_subnet_self_links["0"]
      }
    }
  )
}

resource "google_compute_instance" "this" {
  for_each = var.instances

  name         = each.value.name
  zone         = local.instance_networks[each.key].zone
  machine_type = each.value.gcp_machine_type
  tags         = each.value.tags

  boot_disk {
    initialize_params {
      image = each.value.gcp_image
      size  = each.value.disk_size_gb
    }
  }

  network_interface {
    network    = var.network_self_link
    subnetwork = local.instance_networks[each.key].subnetwork
    network_ip = each.value.private_ip

    dynamic "access_config" {
      for_each = each.value.public_ip ? [1] : []
      content {}
    }
  }

  dynamic "service_account" {
    for_each = var.app_service_account_email != null && contains(var.app_names, each.key) ? [1] : []
    content {
      email  = var.app_service_account_email
      scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    }
  }

  metadata = {
    ssh-keys               = "${var.ssh.user}:${var.ssh_public_key}"
    block-project-ssh-keys = "true"
    enable-oslogin         = "FALSE"
  }
}
