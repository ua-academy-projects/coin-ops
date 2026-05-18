resource "azurerm_route_table" "this" {
  name                = local.route.name
  location            = data.azurerm_resource_group.this.location
  resource_group_name = data.azurerm_resource_group.this.name
}

resource "azurerm_route" "default_egress" {
  name                   = "default-egress"
  resource_group_name    = data.azurerm_resource_group.this.name
  route_table_name       = azurerm_route_table.this.name
  address_prefix         = local.route.destination_range
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = local.route.next_hop_ip
}

resource "azurerm_subnet_route_table_association" "private" {
  for_each = var.private_subnet_ids

  subnet_id      = each.value
  route_table_id = azurerm_route_table.this.id
}
