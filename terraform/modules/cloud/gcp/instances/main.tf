locals {
  fallback_sizes = {
    micro  = "e2-micro"
    small  = "e2-small"
    medium = "e2-standard-2"
    large  = "e2-standard-4"
  }
  sizes = length(var.instance_sizes) > 0 ? var.instance_sizes : local.fallback_sizes

  fallback = {
    instance_size    = "micro"
    os_image         = "debian-cloud/debian-12"
    disk_size        = 10
    zone             = "europe-central2-a"
    subnet           = "internal"
    has_public_ip    = false
    role             = ""
    can_ip_forward   = false
    startup_script   = ""
    user_init_script = ""
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

  ssh_user = trimspace(var.username)

  # Pre-render startup scripts per instance.
  # user_init_script (from general) runs on every VM and handles user creation + SSH port.
  # startup_script (per-instance) contains cloud-specific init (e.g. NAT bootstrap for nat-1).
  # Both are combined into a single startup-script metadata entry.
  instance_scripts = {
    for name, cfg in local.instances : name => join("\n\n", compact([
      cfg.user_init_script != "" ? templatefile("${path.root}/${cfg.user_init_script}", {
        username       = var.username
        ssh_public_key = var.ssh_public_key
        ssh_port       = var.ssh_port
        hostname       = "gcp-${name}"
      }) : "",
      cfg.startup_script != "" ? templatefile("${path.root}/${cfg.startup_script}", {
        private_subnet_cidr = var.private_subnet_cidr
        vpc_cidr            = var.vpc_cidr
      }) : "",
    ]))
  }
}

resource "google_compute_instance" "vm" {
  for_each = local.instances

  name           = each.key
  machine_type   = local.sizes[each.value.instance_size]
  zone           = each.value.zone
  can_ip_forward = each.value.can_ip_forward

  # Network tags: role tag for firewall targeting; "internal-vm" for NAT route.
  # Also add standard http/https-server tags for UI nodes to satisfy GCP defaults.
  tags = concat(
    each.value.role != "" ? [each.value.role] : [],
    each.value.role == "app-ui" ? ["http-server", "https-server"] : [],
    !each.value.has_public_ip ? ["internal-vm"] : []
  )

  # Phase 5: labels for cloud-native Ansible inventory (gcp_compute plugin groups by labels.role).
  labels = {
    role    = each.value.role != "" ? each.value.role : "unset"
    project = var.project_name
    cloud   = "gcp"
  }

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
    local.instance_scripts[each.key] != "" ? {
      startup-script = local.instance_scripts[each.key]
    } : {}
  )
}
