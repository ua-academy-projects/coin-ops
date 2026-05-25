# ═════════════════════════════════════════════════════════════════════════════
# AZURE VIRTUAL MACHINES
# ═════════════════════════════════════════════════════════════════════════════

# ── Public IPs (if needed) ───────────────────────────────────────────────────
resource "azurerm_public_ip" "this" {
  for_each            = { for k, v in local.resolved_vms : k => v if v.public_ip && var.cloud_provider == "azure" }
  name                = "${each.key}-pip"
  location            = var.region
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = merge(var.common_tags, each.value.tags)
}

# ── Network Interfaces ───────────────────────────────────────────────────────
resource "azurerm_network_interface" "this" {
  for_each            = var.cloud_provider == "azure" ? local.resolved_vms : {}
  name                = "${each.key}-nic"
  location            = var.region
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_ids[each.value.subnet_name]
    private_ip_address_allocation = each.value.private_ip != null ? "Static" : "Dynamic"
    private_ip_address            = each.value.private_ip
    public_ip_address_id          = each.value.public_ip ? azurerm_public_ip.this[each.key].id : null
  }

  tags = merge(var.common_tags, each.value.tags)
}

# ── Virtual Machines ─────────────────────────────────────────────────────────
resource "azurerm_linux_virtual_machine" "this" {
  for_each = var.cloud_provider == "azure" ? local.resolved_vms : {}

  name                = each.key
  resource_group_name = var.resource_group_name
  location            = var.region
  size                = each.value.instance_type
  admin_username      = var.ssh_user

  network_interface_ids = [
    azurerm_network_interface.this[each.key].id,
  ]

  dynamic "admin_ssh_key" {
    for_each = var.ssh_public_key != "" ? [1] : []
    content {
      username   = var.ssh_user
      public_key = var.ssh_public_key
    }
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = each.value.disk_type
    disk_size_gb         = each.value.disk_size_gb
  }

  source_image_reference {
    publisher = split(":", each.value.image)[0]
    offer     = split(":", each.value.image)[1]
    sku       = split(":", each.value.image)[2]
    version   = "latest"
  }

  custom_data = each.value.startup_script != "" ? base64encode(each.value.startup_script) : null

  tags = merge(var.common_tags, each.value.tags)

  # Ignore changes to custom_data as it might re-create the VM
  lifecycle {
    ignore_changes = [custom_data]
  }
}
