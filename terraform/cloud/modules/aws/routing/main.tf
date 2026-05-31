# main.tf

resource "aws_route_table" "private" {
  vpc_id = var.network_id

  tags = {
    Name = local.route.name
  }
}

resource "aws_route" "nat_default_egress" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = local.route.destination_range
  network_interface_id   = local.route.next_hop_interface_id
}

resource "aws_route_table_association" "private" {
  for_each = var.private_subnet_ids

  subnet_id      = each.value
  route_table_id = aws_route_table.private.id
}
