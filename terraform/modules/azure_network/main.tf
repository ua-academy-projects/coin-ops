resource "azurerm_resource_group" "main" {
  count    = contains(["azure", "hybrid"], var.config.general.cloud) ? 1 : 0
  name     = "coinops-rg"
  location = var.config.locations[var.config.general.location].azure.region
}

resource "azurerm_virtual_network" "main" {
  count               = contains(["azure", "hybrid"], var.config.general.cloud) ? 1 : 0
  name                = "coinops-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main[0].location
  resource_group_name = azurerm_resource_group.main[0].name
}

resource "azurerm_subnet" "public" {
  count                = contains(["azure", "hybrid"], var.config.general.cloud) ? 1 : 0
  name                 = "coinops-public-subnet"
  resource_group_name  = azurerm_resource_group.main[0].name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "public_b" {
  count                = contains(["azure", "hybrid"], var.config.general.cloud) ? 1 : 0
  name                 = "coinops-public-subnet-b"
  resource_group_name  = azurerm_resource_group.main[0].name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = ["10.0.5.0/24"]
}

resource "azurerm_subnet" "private" {
  count                = contains(["azure", "hybrid"], var.config.general.cloud) ? 1 : 0
  name                 = "coinops-private-subnet"
  resource_group_name  = azurerm_resource_group.main[0].name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_subnet" "private_b" {
  count                = contains(["azure", "hybrid"], var.config.general.cloud) ? 1 : 0
  name                 = "coinops-private-subnet-b"
  resource_group_name  = azurerm_resource_group.main[0].name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = ["10.0.4.0/24"]
}