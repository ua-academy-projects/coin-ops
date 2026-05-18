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

resource "azurerm_route_table" "private_egress" {
  count = var.nat_route != null ? 1 : 0

  name                = var.nat_route.name
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_route" "private_default_egress" {
  count = var.nat_route != null ? 1 : 0

  name                   = "default-egress"
  resource_group_name    = data.azurerm_resource_group.this.name
  route_table_name       = azurerm_route_table.private_egress[0].name
  address_prefix         = var.nat_route.destination_range
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.nat_route.next_hop_ip
}

resource "azurerm_subnet_route_table_association" "private" {
  for_each = var.nat_route != null ? local.private_subnets : {}

  subnet_id      = azurerm_subnet.this[each.key].id
  route_table_id = azurerm_route_table.private_egress[0].id
}
