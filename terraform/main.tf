terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Network ──────────────────────────────────────────────────────
resource "aws_vpc" "coin_ops" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "coin-ops-vpc" }
}

resource "aws_subnet" "coin_ops" {
  vpc_id                  = aws_vpc.coin_ops.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags = { Name = "coin-ops-subnet" }
}

resource "aws_internet_gateway" "coin_ops" {
  vpc_id = aws_vpc.coin_ops.id
  tags   = { Name = "coin-ops-igw" }
}

resource "aws_route_table" "coin_ops" {
  vpc_id = aws_vpc.coin_ops.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.coin_ops.id
  }
  tags = { Name = "coin-ops-rt" }
}

resource "aws_route_table_association" "coin_ops" {
  subnet_id      = aws_subnet.coin_ops.id
  route_table_id = aws_route_table.coin_ops.id
}

# ── Security groups ───────────────────────────────────────────────
resource "aws_security_group" "internal" {
  name   = "coin-ops-internal"
  vpc_id = aws_vpc.coin_ops.id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.0.0.0/16"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ssh" {
  name   = "coin-ops-ssh"
  vpc_id = aws_vpc.coin_ops.id
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }
}

resource "aws_security_group" "web" {
  name   = "coin-ops-web"
  vpc_id = aws_vpc.coin_ops.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── EC2 instances ─────────────────────────────────────────────────
# node-01: History service (PostgreSQL + RabbitMQ + Python)
resource "aws_instance" "node_history" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.coin_ops.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.internal.id, aws_security_group.ssh.id]
  tags = { Name = "softserve-node-01", Role = "history" }
}

# node-02: Proxy service (Go)
resource "aws_instance" "node_proxy" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.coin_ops.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.internal.id, aws_security_group.ssh.id]
  tags = { Name = "softserve-node-02", Role = "proxy" }
}

# node-03: Web UI (nginx)
resource "aws_instance" "node_ui" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.coin_ops.id
  key_name               = var.key_pair_name
  vpc_security_group_ids = [
    aws_security_group.internal.id,
    aws_security_group.ssh.id,
    aws_security_group.web.id,
  ]
  tags = { Name = "softserve-node-03", Role = "ui" }
}
