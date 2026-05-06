resource "aws_route_table" "private" {
  vpc_id = var.vpc_id

  tags = { Name = var.route_table_name }
}

resource "aws_route" "private_default_via_nat_instance" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = var.destination_cidr
  network_interface_id   = var.nat_network_interface_id
}

resource "aws_route_table_association" "private" {
  for_each = var.private_subnet_ids

  subnet_id      = each.value
  route_table_id = aws_route_table.private.id
}
