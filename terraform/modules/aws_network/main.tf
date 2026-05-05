locals {
  fallback_subnets = {
    internal = { cidr = "10.10.1.0/24" }
    external = { cidr = "10.10.2.0/24", public = true }
  }
  subnets        = length(var.subnets) > 0 ? var.subnets : local.fallback_subnets
  public_subnets = { for name, cfg in local.subnets : name => cfg if lookup(cfg, "public", false) }
}

resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr
  tags       = { Name = var.vpc_name }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
  tags   = { Name = "${var.vpc_name}-igw" }
}

resource "aws_subnet" "subnet" {
  for_each = local.subnets

  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = each.value.cidr
  availability_zone       = var.zone
  map_public_ip_on_launch = lookup(each.value, "public", false)

  tags = { Name = "${each.key}-subnet" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "${var.vpc_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  for_each       = local.public_subnets
  subnet_id      = aws_subnet.subnet[each.key].id
  route_table_id = aws_route_table.public.id
}
