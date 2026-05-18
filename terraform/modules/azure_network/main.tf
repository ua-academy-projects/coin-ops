data "azurerm_resource_group" "main" {
  count = var.config.general.cloud == "azure" ? 1 : 0
  name  = "coinops-rg"
}

resource "azurerm_virtual_network" "main" {
  count               = var.config.general.cloud == "azure" ? 1 : 0
  name                = "coinops-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = data.azurerm_resource_group.main[0].location
  resource_group_name = data.azurerm_resource_group.main[0].name
}

resource "azurerm_subnet" "public" {
  count                = var.config.general.cloud == "azure" ? 1 : 0
  name                 = "coinops-public-subnet"
  resource_group_name  = data.azurerm_resource_group.main[0].name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "public_b" {
  count                = var.config.general.cloud == "azure" ? 1 : 0
  name                 = "coinops-public-subnet-b"
  resource_group_name  = data.azurerm_resource_group.main[0].name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = ["10.0.5.0/24"]
}

resource "azurerm_subnet" "private" {
  count                = var.config.general.cloud == "azure" ? 1 : 0
  name                 = "coinops-private-subnet"
  resource_group_name  = data.azurerm_resource_group.main[0].name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_subnet" "private_b" {
  count                = var.config.general.cloud == "azure" ? 1 : 0
  name                 = "coinops-private-subnet-b"
  resource_group_name  = data.azurerm_resource_group.main[0].name
  virtual_network_name = azurerm_virtual_network.main[0].name
  address_prefixes     = ["10.0.4.0/24"]
}