# main.tf

resource "azurerm_virtual_network" "this" {
  name                = var.network.name
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
  address_space       = [var.network.cidr]
}

resource "azurerm_subnet" "this" {
  for_each = local.subnets

  name                 = "${var.network.name}-${each.key}"
  resource_group_name  = data.azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value.cidr]
}
