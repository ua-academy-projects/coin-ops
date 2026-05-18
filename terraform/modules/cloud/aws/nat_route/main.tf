moved {
  from = aws_route.private_default_via_nat_instance
  to   = aws_route.private_via_nat_instance
}

resource "aws_route" "private_via_nat_instance" {
  for_each = var.private_route_table_id != "" ? var.private_routes : {}

  route_table_id         = var.private_route_table_id
  destination_cidr_block = each.value.destination_cidr
  network_interface_id   = var.nat_network_interface_id
}

resource "aws_route" "public_via_nat_instance" {
  for_each = var.public_route_table_id != "" ? var.public_routes : {}

  route_table_id         = var.public_route_table_id
  destination_cidr_block = each.value.destination_cidr
  network_interface_id   = var.nat_network_interface_id
}
