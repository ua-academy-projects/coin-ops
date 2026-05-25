# ═════════════════════════════════════════════════════════════════════════════
# AWS RESOURCES
# ═════════════════════════════════════════════════════════════════════════════

# ─── AWS VPC ─────────────────────────────────────────────────────────────────
resource "aws_vpc" "this" {
  count = var.cloud_provider == "aws" ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.common_tags, {
    Name = var.vpc_name
  })
}

# ─── AWS Subnets ─────────────────────────────────────────────────────────────
resource "aws_subnet" "this" {
  for_each = var.cloud_provider == "aws" ? local.resolved_subnets : {}

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = each.value.cidr
  availability_zone = each.value.zone

  map_public_ip_on_launch = each.value.public

  tags = merge(var.common_tags, {
    Name = each.key
  })
}

# ─── AWS Internet Gateway ───────────────────────────────────────────────────
resource "aws_internet_gateway" "this" {
  count = var.cloud_provider == "aws" ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-igw"
  })
}

# ─── AWS Route Table ────────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  count = var.cloud_provider == "aws" ? 1 : 0

  vpc_id = aws_vpc.this[0].id

  tags = merge(var.common_tags, {
    Name = "${var.vpc_name}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  count = var.cloud_provider == "aws" ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this[0].id
}

resource "aws_route_table_association" "public" {
  for_each = var.cloud_provider == "aws" ? {
    for name, subnet in aws_subnet.this : name => subnet
    if lookup(var.subnets[name], "public", true)
  } : {}

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public[0].id
}

# ─── AWS Security Groups ────────────────────────────────────────────────────
resource "aws_security_group" "this" {
  for_each = var.cloud_provider == "aws" ? {
    for name, rule in var.firewall_rules : rule.target_group => rule...
    if rule.target_group != ""
  } : {}

  name_prefix = "${each.key}-"
  description = "Security group for ${each.key}"
  vpc_id      = aws_vpc.this[0].id

  # Default egress: allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = each.key
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "ingress" {
  for_each = var.cloud_provider == "aws" ? var.firewall_rules : {}

  type              = "ingress"
  security_group_id = aws_security_group.this[each.value.target_group].id
  from_port         = each.value.port
  to_port           = each.value.port
  protocol          = each.value.protocol

  cidr_blocks = length(each.value.source_cidrs) > 0 ? each.value.source_cidrs : null
  source_security_group_id = (
    each.value.source_group != "" && length(each.value.source_cidrs) == 0
    ? aws_security_group.this[each.value.source_group].id
    : null
  )

  description = each.value.description
}
