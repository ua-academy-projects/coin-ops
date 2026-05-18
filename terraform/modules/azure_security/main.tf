data "azurerm_resource_group" "main" {
  count = var.config.general.cloud == "azure" ? 1 : 0
  name  = "coinops-rg"
}

locals {
  rg_name     = try(data.azurerm_resource_group.main[0].name, "")
  rg_location = try(data.azurerm_resource_group.main[0].location, "")
}

resource "azurerm_network_security_group" "jump_host" {
  count               = var.config.general.cloud == "azure" ? 1 : 0
  name                = "jump-host-nsg"
  location            = local.rg_location
  resource_group_name = local.rg_name

  security_rule {
    name                       = "allow-ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = var.config.general.ssh_port
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "internal" {
  count               = var.config.general.cloud == "azure" ? 1 : 0
  name                = "internal-nsg"
  location            = local.rg_location
  resource_group_name = local.rg_name

  security_rule {
    name                       = "allow-ssh-from-jumphost"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = var.config.general.ssh_port
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-internal"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.0.0.0/16"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "web" {
  count               = var.config.general.cloud == "azure" ? 1 : 0
  name                = "web-nsg"
  location            = local.rg_location
  resource_group_name = local.rg_name

  security_rule {
    name                       = "allow-http"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-https"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "db" {
  count               = var.config.general.cloud == "azure" ? 1 : 0
  name                = "db-nsg"
  location            = local.rg_location
  resource_group_name = local.rg_name

  security_rule {
    name                       = "allow-postgres"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = "10.0.0.0/16"
    destination_address_prefix = "*"
  }
}