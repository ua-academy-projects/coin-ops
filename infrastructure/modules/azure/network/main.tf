# ----------------------------------------------------------------------------
# Resource Group — container for all project infrastructure resources
# ----------------------------------------------------------------------------
resource "azurerm_resource_group" "this" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# ----------------------------------------------------------------------------
# Virtual Network — the private network (Azure equivalent of a VPC)
# ----------------------------------------------------------------------------
resource "azurerm_virtual_network" "this" {
  name                = var.name
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

# ----------------------------------------------------------------------------
# Subnets — network segments inside the VNet
# ----------------------------------------------------------------------------
resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                 = each.key
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.cidr]
}
