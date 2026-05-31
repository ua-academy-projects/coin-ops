# main.tf

resource "aws_security_group" "workload" {
  for_each = local.workload_security_groups

  name        = each.key
  description = each.value.description
  vpc_id      = var.network_id

  tags = {
    Name = each.key
  }
}

resource "aws_vpc_security_group_egress_rule" "default" {
  for_each = aws_security_group.workload

  security_group_id = each.value.id
  description       = "Allow all outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "cidr" {
  for_each = {
    for key, rule in local.cidr_rules : key => rule
    if rule.type == "ingress"
  }

  security_group_id = aws_security_group.workload[each.value.target_workload].id
  description       = each.value.description
  ip_protocol       = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  cidr_ipv4         = each.value.cidr_block
}

resource "aws_vpc_security_group_egress_rule" "cidr" {
  for_each = {
    for key, rule in local.cidr_rules : key => rule
    if rule.type == "egress"
  }

  security_group_id = aws_security_group.workload[each.value.target_workload].id
  description       = each.value.description
  ip_protocol       = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  cidr_ipv4         = each.value.cidr_block
}

resource "aws_vpc_security_group_ingress_rule" "source_sg" {
  for_each = {
    for key, rule in local.source_workload_port_rules : key => rule
    if rule.type == "ingress"
  }

  security_group_id            = aws_security_group.workload[each.value.target_workload].id
  description                  = each.value.description
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  referenced_security_group_id = aws_security_group.workload[each.value.source_workload].id
}

resource "aws_vpc_security_group_egress_rule" "source_sg" {
  for_each = {
    for key, rule in local.source_workload_port_rules : key => rule
    if rule.type == "egress"
  }

  security_group_id            = aws_security_group.workload[each.value.target_workload].id
  description                  = each.value.description
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  referenced_security_group_id = aws_security_group.workload[each.value.source_workload].id
}
