locals {
  common_tags = {
    project = "azure-monitoring-lab"
    managed = "terraform"
  }

  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
}

data "azurerm_resource_group" "nav" {
  name = var.resource_group_name
}

resource "azurerm_virtual_network" "nav" {
  name                = "${var.prefix}-vnet"
  address_space       = ["10.20.0.0/16"]
  location            = data.azurerm_resource_group.nav.location
  resource_group_name = data.azurerm_resource_group.nav.name
  tags                = local.common_tags
}

resource "azurerm_subnet" "nav" {
  name                 = "${var.prefix}-subnet"
  resource_group_name  = data.azurerm_resource_group.nav.name
  virtual_network_name = azurerm_virtual_network.nav.name
  address_prefixes     = ["10.20.1.0/24"]
}

resource "azurerm_public_ip" "nav" {
  name                = "${var.prefix}-pip"
  resource_group_name = data.azurerm_resource_group.nav.name
  location            = data.azurerm_resource_group.nav.location
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

resource "azurerm_network_security_group" "nav" {
  name                = "${var.prefix}-nsg"
  location            = data.azurerm_resource_group.nav.location
  resource_group_name = data.azurerm_resource_group.nav.name
  tags                = local.common_tags

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.allowed_ssh_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "nav" {
  name                = "${var.prefix}-nic"
  location            = data.azurerm_resource_group.nav.location
  resource_group_name = data.azurerm_resource_group.nav.name
  tags                = local.common_tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.nav.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.nav.id
  }
}

resource "azurerm_network_interface_security_group_association" "nav" {
  network_interface_id      = azurerm_network_interface.nav.id
  network_security_group_id = azurerm_network_security_group.nav.id
}

resource "azurerm_linux_virtual_machine" "nav" {
  name                            = var.vm_name
  resource_group_name             = data.azurerm_resource_group.nav.name
  location                        = data.azurerm_resource_group.nav.location
  size                            = var.vm_size
  admin_username                  = var.admin_username
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.nav.id]
  tags                            = local.common_tags

  admin_ssh_key {
    username   = var.admin_username
    public_key = local.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }
}

resource "azurerm_monitor_action_group" "nav" {
  name                = "${var.prefix}-alerts"
  resource_group_name = data.azurerm_resource_group.nav.name
  short_name          = "navalert"
  tags                = local.common_tags

  email_receiver {
    name                    = "primary-email"
    email_address           = var.alert_email
    use_common_alert_schema = true
  }
}

resource "azurerm_monitor_metric_alert" "nav" {
  name                = "${var.prefix}-cpu-alert"
  resource_group_name = data.azurerm_resource_group.nav.name
  scopes              = [azurerm_linux_virtual_machine.nav.id]
  description         = "Alert when average VM CPU usage is above the configured threshold."
  severity            = var.cpu_alert_severity
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.common_tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.cpu_alert_threshold
  }

  action {
    action_group_id = azurerm_monitor_action_group.nav.id
  }
}
