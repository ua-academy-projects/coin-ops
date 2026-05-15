locals {
  fallback_rules = {
    "allow-ssh-external" = {
      protocols    = [{ protocol = "tcp", ports = ["22"] }]
      source_cidrs = ["0.0.0.0/0"]
      target_role  = "jump-host"
    }
    "allow-internal" = {
      protocols   = [{ protocol = "tcp", ports = ["22"] }, { protocol = "icmp" }]
      source_role = "jump-host"
      target_role = "internal-vm"
    }
  }
  rules = jsondecode(
    length(var.firewall_rules) > 0
    ? jsonencode(var.firewall_rules)
    : jsonencode(local.fallback_rules)
  )

  target_roles = toset([for name, rule in local.rules : rule.target_role])

  flat_rules = flatten([
    for rule_name, rule in local.rules : [
      for proto in rule.protocols :
      # ICMP has no port concept — single rule with -1/-1.
      proto.protocol == "icmp"
      ? [{
        key          = "${rule_name}-icmp"
        target_role  = rule.target_role
        protocol     = "icmp"
        from_port    = -1
        to_port      = -1
        source_cidrs = lookup(rule, "source_cidrs", null)
        source_role  = lookup(rule, "source_role", null)
      }]
      # Each port/range entry becomes its own SG rule so all ports in the list are applied.
      : [
        for port in lookup(proto, "ports", []) : {
          key          = "${rule_name}-${proto.protocol}-${port}"
          target_role  = rule.target_role
          protocol     = proto.protocol
          from_port    = tonumber(split("-", port)[0])
          to_port      = length(split("-", port)) > 1 ? tonumber(split("-", port)[1]) : tonumber(split("-", port)[0])
          source_cidrs = lookup(rule, "source_cidrs", null)
          source_role  = lookup(rule, "source_role", null)
        }
      ]
    ]
  ])
  flat_rules_map = { for r in local.flat_rules : r.key => r }
}

resource "aws_security_group" "sg" {
  for_each = local.target_roles

  name        = "${each.key}-sg"
  description = "Security group for ${each.key}"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.egress_cidrs
  }

  tags = { Name = "${each.key}-sg" }
}

resource "aws_security_group_rule" "ingress" {
  for_each = local.flat_rules_map

  type                     = "ingress"
  security_group_id        = aws_security_group.sg[each.value.target_role].id
  protocol                 = each.value.protocol
  from_port                = each.value.from_port
  to_port                  = each.value.to_port
  cidr_blocks              = each.value.source_cidrs
  source_security_group_id = each.value.source_role != null ? aws_security_group.sg[each.value.source_role].id : null
}
