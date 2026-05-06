locals {
  config  = yamldecode(file("${path.module}/config.yaml"))
  general = local.config.general
}

# --- SSH Key Pair ---
resource "aws_key_pair" "ssh_key" {
  key_name   = "devops-key"
  public_key = file("${pathexpand("~")}/.ssh/id_ed25519.pub")
}

# --- VPC ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "devops-network" }
}

# --- Internet Gateway (AWS requires this explicitly) ---
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "devops-igw" }
}

# --- Public Subnet (for jump host) ---
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${local.general.region}a"

  tags = { Name = "devops-public-subnet" }
}

# --- Private Subnet (for internal VMs) ---
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${local.general.region}a"

  tags = { Name = "devops-private-subnet" }
}

# --- Route Table: public subnet → internet ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "devops-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Security Group: jump host (SSH from internet on custom port) ---
resource "aws_security_group" "jump_host" {
  name        = "jump-host-sg"
  description = "Allow SSH on custom port from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = tonumber(local.general.ssh_port)
    to_port     = tonumber(local.general.ssh_port)
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "jump-host-sg" }
}

# --- Security Group: internal VMs (SSH from jump host only) ---
resource "aws_security_group" "internal" {
  name        = "internal-sg"
  description = "Allow SSH from jump host, all traffic between internal VMs"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = tonumber(local.general.ssh_port)
    to_port         = tonumber(local.general.ssh_port)
    protocol        = "tcp"
    security_groups = [aws_security_group.jump_host.id]
  }

  ingress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "internal-sg" }
}

# --- VMs ---
module "vm" {
  for_each = local.config.vms
  source   = "./modules/vm"

  name          = each.key
  instance_type = try(each.value.instance_type, local.general.instance_type)
  ami           = try(each.value.ami, local.general.ami)
  disk_size     = try(each.value.disk_size, local.general.disk_size)
  tags          = each.value.tags
  public_ip     = each.value.public_ip
  subnet_id     = each.value.public_ip ? aws_subnet.public.id : aws_subnet.private.id
  key_name      = aws_key_pair.ssh_key.key_name
  ssh_user      = local.general.ops_user
  ssh_port      = local.general.ssh_port

  vpc_security_group_ids = each.value.public_ip ? [aws_security_group.jump_host.id] : [aws_security_group.internal.id]
}