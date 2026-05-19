resource "azurerm_public_ip" "this" {
  for_each = {
    for key, instance in local.instances : key => instance
    if instance.assign_public_ip
  }

  name                = "pip-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Dynamic"
  sku                 = "Standard"
  zones               = [each.value.zone]

  lifecycle {
    create_before_destroy = true
  }
}

resource "azurerm_network_interface" "this" {
  for_each = local.instances

  name                           = "nic-${each.key}"
  location                       = var.location
  resource_group_name            = var.resource_group_name
  ip_forwarding_enabled          = each.value.can_ip_forward
  accelerated_networking_enabled = false

  ip_configuration {
    name                          = "primary"
    subnet_id                     = each.value.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = try(azurerm_public_ip.this[each.key].id, null)
    primary                       = true
  }
}

resource "azurerm_network_interface_application_security_group_association" "this" {
  for_each = local.instances

  network_interface_id          = azurerm_network_interface.this[each.key].id
  application_security_group_id = var.application_security_group_ids[each.key]
}

resource "azurerm_linux_virtual_machine" "this" {
  for_each = local.instances

  name                            = each.key
  resource_group_name             = var.resource_group_name
  location                        = var.location
  size                            = each.value.vm_size
  admin_username                  = "deployer"
  zone                            = each.value.zone
  network_interface_ids           = [azurerm_network_interface.this[each.key].id]
  disable_password_authentication = true

  admin_ssh_key {
    username   = "deployer"
    public_key = trimspace(file(var.ssh_public_key_path))
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = each.value.disk_size_gb
  }

  source_image_reference {
    publisher = split(":", each.value.image)[0]
    offer     = split(":", each.value.image)[1]
    sku       = split(":", each.value.image)[2]
    version   = split(":", each.value.image)[3]
  }

  dynamic "identity" {
    for_each = each.value.managed_identity ? [1] : []

    content {
      type = "SystemAssigned"
    }
  }

  tags = merge(
    { for tag in each.value.tags : tag => "true" },
    {
      Name = each.key
    }
  )
}
