moved {
  from = azurerm_route_table.this
  to   = azurerm_route_table.private
}

resource "azurerm_route_table" "private" {
  name                = var.route_table_name
  location            = var.location
  resource_group_name = var.resource_group_name

  dynamic "route" {
    for_each = var.private_routes
    content {
      name                   = route.key
      address_prefix         = route.value.destination_cidr
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.next_hop_ip
    }
  }
}

resource "azurerm_subnet_route_table_association" "private" {
  for_each       = var.private_subnet_ids
  subnet_id      = each.value
  route_table_id = azurerm_route_table.private.id
}

resource "azurerm_route_table" "public" {
  count               = length(var.public_routes) > 0 && length(var.public_subnet_ids) > 0 ? 1 : 0
  name                = "${var.route_table_name}-public"
  location            = var.location
  resource_group_name = var.resource_group_name

  dynamic "route" {
    for_each = var.public_routes
    content {
      name                   = route.key
      address_prefix         = route.value.destination_cidr
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.next_hop_ip
    }
  }
}

resource "azurerm_subnet_route_table_association" "public" {
  for_each       = length(var.public_routes) > 0 ? var.public_subnet_ids : {}
  subnet_id      = each.value
  route_table_id = azurerm_route_table.public[0].id
}
