# ----------------------------------------------------------------------------
# SSH Key — project-wide metadata
# ----------------------------------------------------------------------------
resource "google_compute_project_metadata" "ssh_keys" {
  metadata = {
    ssh-keys = "${local.general.ssh_user}:${var.ssh_public_key}"
  }
}

# ----------------------------------------------------------------------------
# Networks — one module call per network in JSON
# ----------------------------------------------------------------------------
module "network" {
  source   = "../../modules/network"
  for_each = local.networks.networks

  project_id  = local.general.project_id
  name        = each.key
  description = lookup(each.value, "description", "")

  # Pass only subnets that belong to this network
  subnets = {
    for subnet_name, subnet in local.networks.subnets :
    subnet_name => {
      cidr   = subnet.cidr
      region = subnet.region
    }
    if subnet.network == each.key
  }
}

# ----------------------------------------------------------------------------
# Firewall rules — one module call per rule in JSON
# ----------------------------------------------------------------------------
module "firewall" {
  source   = "../../modules/firewall"
  for_each = local.firewall.firewall_rules

  project_id        = local.general.project_id
  name              = each.key
  network_self_link = module.network[each.value.network].network_self_link

  protocol      = lookup(each.value, "protocol", null)
  protocols     = lookup(each.value, "protocols", [])
  ports         = lookup(each.value, "ports", [])
  source_ranges = lookup(each.value, "source_ranges", [])
  source_tags   = lookup(each.value, "source_tags", [])
  target_tags   = each.value.target_tags
  description   = each.value.description
}

# ----------------------------------------------------------------------------
# VMs — one module call per VM in JSON
# ----------------------------------------------------------------------------
module "vm" {
  source   = "../../modules/vm"
  for_each = local.vms.vms

  project_id   = local.general.project_id
  name         = each.key
  zone         = local.general.zone
  environment  = local.general.environment
  ssh_user     = local.general.ssh_user
  ssh_public_key = var.ssh_public_key
  ssh_port     = local.general.ssh_port

  # Override logic: use VM-specific value if present, otherwise use general default
  machine_type = lookup(each.value, "machine_type", local.general.default_machine_type)
  os_image     = lookup(each.value, "os_image", local.general.default_os)
  disk_size_gb = lookup(each.value, "disk_size_gb", local.general.default_disk_size_gb)
  disk_type    = lookup(each.value, "disk_type", local.general.default_disk_type)

  network_self_link = module.network[each.value.network].network_self_link
  subnet_self_link  = module.network[each.value.network].subnet_self_links[each.value.subnet]

  assign_public_ip = lookup(each.value, "assign_public_ip", false)
  tags             = lookup(each.value, "tags", [])
  labels           = lookup(each.value, "labels", {})
}