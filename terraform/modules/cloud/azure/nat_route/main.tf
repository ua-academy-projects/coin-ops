resource "azurerm_route_table" "this" {
  name                = var.route_table_name
  location            = var.location
  resource_group_name = var.resource_group_name

  route {
    name                   = "default-via-nat"
    address_prefix         = var.destination_cidr
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.next_hop_ip
  }
}

resource "azurerm_subnet_route_table_association" "private" {
  for_each       = var.subnet_ids
  subnet_id      = each.value
  route_table_id = azurerm_route_table.this.id
}
