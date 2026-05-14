locals {
  cloud                 = lower(var.cloud)
  gcp_enabled           = local.cloud == "gcp"
  aws_enabled           = local.cloud == "aws"
  nat_public_subnet_key = "public-a"

  aws_public_subnets = local.aws_enabled ? {
    for name, subnet in var.config.network.aws_subnets : name => subnet
    if subnet.public
  } : {}
  aws_private_subnets = local.aws_enabled ? {
    for name, subnet in var.config.network.aws_subnets : name => subnet
    if !subnet.public
  } : {}
}


resource "google_compute_network" "vpc" {
  count                   = local.gcp_enabled ? 1 : 0
  name                    = var.config.network.name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "subnet" {
  count         = local.gcp_enabled ? 1 : 0
  name          = var.config.network.subnet_name
  ip_cidr_range = var.config.network.cidr
  region        = var.config.project.gcp.region
  network       = google_compute_network.vpc[0].id
}

resource "google_compute_router" "router" {
  count   = local.gcp_enabled ? 1 : 0
  name    = "${var.config.network.name}-router"
  region  = var.config.project.gcp.region
  network = google_compute_network.vpc[0].id
}

resource "google_compute_router_nat" "nat" {
  count                              = local.gcp_enabled ? 1 : 0
  name                               = "${var.config.network.name}-nat"
  router                             = google_compute_router.router[0].name
  region                             = var.config.project.gcp.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.subnet[0].id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

resource "aws_vpc" "main" {
  count                = local.aws_enabled ? 1 : 0
  cidr_block           = var.config.network.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = var.config.network.name
  }
}

resource "aws_internet_gateway" "main" {
  count  = local.aws_enabled ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  tags = {
    Name = "${var.config.network.name}-igw"
  }
}

resource "aws_subnet" "subnets" {
  for_each = local.aws_enabled ? var.config.network.aws_subnets : {}

  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.config.network.name}-${each.key}"
  }
}

resource "aws_route_table" "public" {
  count  = local.aws_enabled ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main[0].id
  }

  tags = {
    Name = "${var.config.network.name}-public"
  }
}

resource "aws_route_table_association" "public" {
  for_each = local.aws_enabled ? local.aws_public_subnets : {}

  subnet_id      = aws_subnet.subnets[each.key].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_eip" "nat" {
  count  = local.aws_enabled ? 1 : 0
  domain = "vpc"

  tags = {
    Name = "${var.config.network.name}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  count         = local.aws_enabled ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.subnets[local.nat_public_subnet_key].id


  tags = {
    Name = "${var.config.network.name}-nat"
  }

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  count  = local.aws_enabled ? 1 : 0
  vpc_id = aws_vpc.main[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[0].id
  }

  tags = {
    Name = "${var.config.network.name}-private"
  }
}

resource "aws_route_table_association" "private" {
  for_each = local.aws_enabled ? local.aws_private_subnets : {}

  subnet_id      = aws_subnet.subnets[each.key].id
  route_table_id = aws_route_table.private[0].id
}
