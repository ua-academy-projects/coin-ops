resource "aws_security_group" "bastion" {
  name        = "${var.name_prefix}-bastion-sg"
  description = "Allow SSH to bastion"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from allowed external IPs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_source_ranges
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-bastion-sg"
  }
}

resource "aws_security_group" "private" {
  name        = "${var.name_prefix}-private-sg"
  description = "Allow private access from bastion"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  dynamic "ingress" {
    for_each = var.allow_icmp_from_bastion ? [1] : []

    content {
      description     = "ICMP from bastion"
      from_port       = -1
      to_port         = -1
      protocol        = "icmp"
      security_groups = [aws_security_group.bastion.id]
    }
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-private-sg"
  }
}