# Module: vm

Creates a single GCP VM instance. Use with `for_each` to create multiple VMs.

Configures SSH on a custom port, creates a non-root SSH user, and hardens
SSH configuration on first boot via startup script.

## Usage

```hcl
module "vms" {
  source   = "../../modules/vm"
  for_each = local.vms

  name             = each.key
  project_id       = local.general.project_id
  zone             = local.general.zone
  machine_type     = lookup(each.value, "machine_type", local.general.default_machine_type)
  os_image         = lookup(each.value, "os_image", local.general.default_os)
  disk_size_gb     = lookup(each.value, "disk_size_gb", local.general.default_disk_size_gb)
  disk_type        = lookup(each.value, "disk_type", local.general.default_disk_type)
  network_self_link = module.network["terraform-network"].network_self_link
  subnet_self_link  = module.network["terraform-network"].subnet_self_links[each.value.subnet]
  assign_public_ip  = lookup(each.value, "assign_public_ip", false)
  tags              = lookup(each.value, "tags", [])
  labels            = lookup(each.value, "labels", {})
  environment       = local.general.environment
  ssh_user          = local.general.ssh_user
  ssh_public_key    = var.ssh_public_key
  ssh_port          = local.general.ssh_port
}
```

## Inputs

<!-- terraform-docs will auto-generate this section -->

## Outputs

<!-- terraform-docs will auto-generate this section -->