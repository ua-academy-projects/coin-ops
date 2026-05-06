resource "aws_route" "private_default_via_nat_instance" {
  route_table_id         = var.private_route_table_id
  destination_cidr_block = var.destination_cidr
  network_interface_id   = var.nat_network_interface_id
}

