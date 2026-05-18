data "azurerm_resource_group" "main" {
  count = var.config.general.cloud == "azure" ? 1 : 0
  name  = "coinops-rg"
}

locals {
  rg_name     = try(data.azurerm_resource_group.main[0].name, "")
  rg_location = try(data.azurerm_resource_group.main[0].location, "")
}

resource "azurerm_public_ip" "vm" {
  for_each = var.config.general.cloud == "azure" ? {
    for name, vm in var.config.vms : name => vm if vm.public_ip
  } : {}

  name                = "${each.key}-pip"
  location            = local.rg_location
  resource_group_name = local.rg_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = [var.config.locations[var.config.general.location].azure.zones[each.value.zone]]
}

resource "azurerm_network_interface" "vm" {
  for_each = var.config.general.cloud == "azure" ? var.config.vms : {}

  name                = "${each.key}-nic"
  location            = local.rg_location
  resource_group_name = local.rg_name

  ip_configuration {
    name      = "internal"
    subnet_id = each.value.public_ip ? (
      each.value.zone == "secondary" ? var.public_subnet_b_id : var.public_subnet_id
    ) : (
      each.value.zone == "secondary" ? var.private_subnet_b_id : var.private_subnet_id
    )
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = each.value.public_ip ? azurerm_public_ip.vm[each.key].id : null
  }
}

resource "azurerm_network_interface_security_group_association" "jump_host" {
  for_each = var.config.general.cloud == "azure" ? {
    for name, vm in var.config.vms : name => vm if contains(vm.tags, "jump-host")
  } : {}

  network_interface_id      = azurerm_network_interface.vm[each.key].id
  network_security_group_id = var.jump_host_nsg_id
}

resource "azurerm_network_interface_security_group_association" "internal" {
  for_each = var.config.general.cloud == "azure" ? {
    for name, vm in var.config.vms : name => vm if contains(vm.tags, "internal")
  } : {}

  network_interface_id      = azurerm_network_interface.vm[each.key].id
  network_security_group_id = var.internal_nsg_id
}

resource "azurerm_network_interface_security_group_association" "web" {
  for_each = var.config.general.cloud == "azure" ? {
    for name, vm in var.config.vms : name => vm if contains(vm.tags, "web")
  } : {}

  network_interface_id      = azurerm_network_interface.vm[each.key].id
  network_security_group_id = var.web_nsg_id
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each = var.config.general.cloud == "azure" ? var.config.vms : {}

  name                            = each.key
  location                        = local.rg_location
  resource_group_name             = local.rg_name
  size                            = var.config.sizes[each.value.size].azure
  zone                            = var.config.locations[var.config.general.location].azure.zones[each.value.zone]
  admin_username                  = var.config.general.ops_user
  disable_password_authentication = true

  network_interface_ids = [azurerm_network_interface.vm[each.key].id]

  admin_ssh_key {
    username   = var.config.general.ops_user
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
    disk_size_gb         = try(each.value.disk_size, var.config.general.disk_size)
  }

  source_image_reference {
    publisher = split(":", var.config.images.ubuntu_2404.azure)[0]
    offer     = split(":", var.config.images.ubuntu_2404.azure)[1]
    sku       = split(":", var.config.images.ubuntu_2404.azure)[2]
    version   = split(":", var.config.images.ubuntu_2404.azure)[3]
  }

  custom_data = base64encode(<<-EOT
    #!/bin/bash
    if [ -f /etc/ssh/sshd_config.d/custom-port.conf ]; then
      exit 0
    fi
    echo "${var.config.general.ops_user} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${var.config.general.ops_user}
    systemctl disable --now ssh.socket || true
    echo "Port ${var.config.general.ssh_port}" > /etc/ssh/sshd_config.d/custom-port.conf
    systemctl enable ssh.service
    systemctl restart ssh.service
  EOT
  )

  tags = {
    Name = each.key
  }
}