locals {
  app_instances = { for name, inst in var.instances : name => inst if contains(var.app_names, name) }
  k3s_instances = { for name, inst in var.instances : name => inst if contains(var.k3s_names, name) }
  bastions      = { for name, inst in var.instances : name => inst if name == var.bastion_name }

  user_data = <<-EOT
  #cloud-config
  users:
    - name: ${var.ssh.user}
      groups: [sudo]
      shell: /bin/bash
      sudo: ['ALL=(ALL) NOPASSWD:ALL']
      ssh_authorized_keys:
        - ${var.ssh_public_key}
  package_update: true
  packages:
    - python3
  EOT
}

resource "azurerm_public_ip" "bastion" {
  for_each = local.bastions

  name                = "${each.value.name}-pip"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "bastion" {
  for_each = local.bastions

  name                = "${each.value.name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.public_subnet_ids["0"]
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.private_ip
    public_ip_address_id          = azurerm_public_ip.bastion[each.key].id
  }
}

resource "azurerm_network_interface" "app" {
  for_each = local.app_instances

  name                = "${each.value.name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.private_subnet_ids[coalesce(try(each.value.subnet_key, null), tostring(index(var.app_names, each.key) % length(var.private_subnet_ids)))]
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.private_ip
  }
}

resource "azurerm_linux_virtual_machine" "bastion" {
  for_each = local.bastions

  name                            = each.value.name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = each.value.azure_vm_size
  admin_username                  = var.ssh.user
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.bastion[each.key].id]
  custom_data                     = base64encode(local.user_data)

  identity {
    type = "SystemAssigned"
  }

  admin_ssh_key {
    username   = var.ssh.user
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = max(each.value.disk_size_gb, 30)
  }

  source_image_reference {
    publisher = each.value.azure_image.publisher
    offer     = each.value.azure_image.offer
    sku       = each.value.azure_image.sku
    version   = each.value.azure_image.version
  }
}

resource "azurerm_network_interface" "k3s" {
  for_each = local.k3s_instances

  name                = "${each.value.name}-nic"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "primary"
    subnet_id                     = var.private_subnet_ids[coalesce(try(each.value.subnet_key, null), tostring(index(var.k3s_names, each.key) % length(var.private_subnet_ids)))]
    private_ip_address_allocation = "Static"
    private_ip_address            = each.value.private_ip
  }
}

resource "azurerm_linux_virtual_machine" "k3s" {
  for_each = local.k3s_instances

  name                            = each.value.name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = each.value.azure_vm_size
  admin_username                  = var.ssh.user
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.k3s[each.key].id]
  custom_data                     = base64encode(local.user_data)

  identity {
    type = "SystemAssigned"
  }

  admin_ssh_key {
    username   = var.ssh.user
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = max(each.value.disk_size_gb, 30)
  }

  source_image_reference {
    publisher = each.value.azure_image.publisher
    offer     = each.value.azure_image.offer
    sku       = each.value.azure_image.sku
    version   = each.value.azure_image.version
  }
}

resource "azurerm_linux_virtual_machine" "app" {
  for_each = local.app_instances

  name                            = each.value.name
  location                        = var.location
  resource_group_name             = var.resource_group_name
  size                            = each.value.azure_vm_size
  admin_username                  = var.ssh.user
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.app[each.key].id]
  custom_data                     = base64encode(local.user_data)

  identity {
    type = "SystemAssigned"
  }

  admin_ssh_key {
    username   = var.ssh.user
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = max(each.value.disk_size_gb, 30)
  }

  source_image_reference {
    publisher = each.value.azure_image.publisher
    offer     = each.value.azure_image.offer
    sku       = each.value.azure_image.sku
    version   = each.value.azure_image.version
  }
}
