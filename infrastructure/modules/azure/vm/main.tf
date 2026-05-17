# ----------------------------------------------------------------------------
# Parse the OS image string "publisher:offer:sku:version" into parts
# ----------------------------------------------------------------------------
locals {
  image_parts = split(":", var.os_image)
  image = {
    publisher = local.image_parts[0]
    offer     = local.image_parts[1]
    sku       = local.image_parts[2]
    version   = local.image_parts[3]
  }

  # cloud-init script: configure custom SSH port on first boot
  custom_data = base64encode(<<-EOF
    #!/bin/bash
    set -e
    sed -i "s/^#*Port .*/Port ${var.ssh_port}/" /etc/ssh/sshd_config
    sed -i "s/^#*PermitRootLogin .*/PermitRootLogin no/" /etc/ssh/sshd_config
    sed -i "s/^#*PasswordAuthentication .*/PasswordAuthentication no/" /etc/ssh/sshd_config
    systemctl restart sshd || systemctl restart ssh
  EOF
  )
}

# ----------------------------------------------------------------------------
# Public IP — created only when assign_public_ip is true (jump host)
# ----------------------------------------------------------------------------
resource "azurerm_public_ip" "this" {
  count = var.assign_public_ip ? 1 : 0

  name                = "${var.name}-public-ip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

# ----------------------------------------------------------------------------
# Network Interface — the VM's network card
# ----------------------------------------------------------------------------
resource "azurerm_network_interface" "this" {
  name                = "${var.name}-nic"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.assign_public_ip ? azurerm_public_ip.this[0].id : null
  }
}

# ----------------------------------------------------------------------------
# Attach the Network Security Group to the NIC
# ----------------------------------------------------------------------------
resource "azurerm_network_interface_security_group_association" "this" {
  network_interface_id      = azurerm_network_interface.this.id
  network_security_group_id = var.nsg_id
}

# ----------------------------------------------------------------------------
# Linux Virtual Machine
# ----------------------------------------------------------------------------
resource "azurerm_linux_virtual_machine" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.instance_type
  admin_username      = var.ssh_user
  tags                = var.tags

  network_interface_ids = [azurerm_network_interface.this.id]

  admin_ssh_key {
    username   = var.ssh_user
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = var.disk_type
    disk_size_gb         = var.disk_size_gb
  }

  source_image_reference {
    publisher = local.image.publisher
    offer     = local.image.offer
    sku       = local.image.sku
    version   = local.image.version
  }

  custom_data = local.custom_data

  # The NSG must be attached before the VM is considered ready
  depends_on = [azurerm_network_interface_security_group_association.this]
}
