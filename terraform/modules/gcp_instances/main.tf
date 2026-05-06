locals {
  fallback_sizes = {
    micro  = "e2-micro"
    small  = "e2-small"
    medium = "e2-standard-2"
    large  = "e2-standard-4"
  }
  sizes = length(var.instance_sizes) > 0 ? var.instance_sizes : local.fallback_sizes

  fallback = {
    instance_size  = "micro"
    os_image       = "debian-cloud/debian-12"
    disk_size      = 10
    zone           = "europe-central2-a"
    subnet         = "internal"
    has_public_ip  = false
    role           = ""
    can_ip_forward = false
    startup_script = ""
  }

  fallback_instances = { "default-vm" = {} }
  source_instances = jsondecode(
    length(var.instances) > 0
    ? jsonencode(var.instances)
    : jsonencode(local.fallback_instances)
  )

  instances = {
    for name, cfg in local.source_instances : name => merge(
      local.fallback,
      var.defaults,
      var.cloud_defaults,
      cfg
    )
  }

  ssh_user = lookup(var.cloud_defaults, "ssh_user", "debian")
}

resource "google_compute_instance" "vm" {
  for_each = local.instances

  name           = each.key
  machine_type   = local.sizes[each.value.instance_size]
  zone           = each.value.zone
  can_ip_forward = each.value.can_ip_forward

  # VMs without a public IP receive the "internal-vm" tag so the NAT route applies to them.
  tags = concat(
    each.value.role != "" ? [each.value.role] : [],
    !each.value.has_public_ip ? ["internal-vm"] : []
  )

  boot_disk {
    initialize_params {
      image = each.value.os_image
      size  = each.value.disk_size
    }
  }

  network_interface {
    network    = var.network_id
    subnetwork = var.subnet_ids[each.value.subnet]

    dynamic "access_config" {
      for_each = each.value.has_public_ip ? [1] : []
      content {}
    }
  }

  metadata = merge(
    {
      # Keep SSH auth deterministic: only instance-level keys from Terraform.
      # This prevents accidental project-level key injection (e.g. gcloud default key).
      block-project-ssh-keys = "true"
    },
    var.ssh_public_key != "" ? {
      ssh-keys = "${local.ssh_user}:${var.ssh_public_key}"
    } : {},
    each.value.startup_script != "" ? {
      startup-script = templatefile("${path.root}/${each.value.startup_script}", {
        private_subnet_cidr = var.private_subnet_cidr
      })
    } : {}
  )
}
