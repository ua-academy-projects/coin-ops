locals {
  kubespray_bootstrap_script = <<-SCRIPT
    #!/bin/bash
    set -euxo pipefail

    if command -v apt-get >/dev/null 2>&1; then
      export DEBIAN_FRONTEND=noninteractive
      apt-get update
      apt-get install -y python3 sudo
    fi

    if id "${var.ssh_user}" >/dev/null 2>&1; then
      usermod -aG sudo "${var.ssh_user}" || true
      cat >/etc/sudoers.d/90-${var.ssh_user}-nopasswd <<EOF
${var.ssh_user} ALL=(ALL) NOPASSWD:ALL
EOF
      chmod 0440 /etc/sudoers.d/90-${var.ssh_user}-nopasswd
    fi
  SCRIPT

  common_tags = merge(
    {
      Project = var.cluster_name
      Managed = "terraform"
      Stack   = "kubespray"
    },
    var.tags,
  )

  nodes = {
    cp-1 = {
      private_ip = var.node_private_ips.cp_1
      role       = "control-plane"
      subnet_key = "private-a"
    }
    cp-2 = {
      private_ip = var.node_private_ips.worker_1
      role       = "control-plane"
      subnet_key = "private-a"
    }
    cp-3 = {
      private_ip = var.node_private_ips.worker_2
      role       = "control-plane"
      subnet_key = "private-b"
    }
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-igw"
  })
}

resource "aws_subnet" "subnets" {
  for_each = {
    public-a = {
      cidr_block        = var.subnet_cidrs.public_a
      availability_zone = var.availability_zones.public_a
      public            = true
    }
    public-b = {
      cidr_block        = var.subnet_cidrs.public_b
      availability_zone = var.availability_zones.public_b
      public            = true
    }
    private-a = {
      cidr_block        = var.subnet_cidrs.private_a
      availability_zone = var.availability_zones.private_a
      public            = false
    }
    private-b = {
      cidr_block        = var.subnet_cidrs.private_b
      availability_zone = var.availability_zones.private_b
      public            = false
    }
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = each.value.public

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-${each.key}"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  for_each = {
    public-a = aws_subnet.subnets["public-a"].id
    public-b = aws_subnet.subnets["public-b"].id
  }

  subnet_id      = each.value
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-nat-eip"
  })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.subnets["public-a"].id

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-nat"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  for_each = {
    private-a = aws_subnet.subnets["private-a"].id
    private-b = aws_subnet.subnets["private-b"].id
  }

  subnet_id      = each.value
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "bastion" {
  name        = "${var.cluster_name}-bastion"
  description = "SSH access to bastion host"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from admin CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_source_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-bastion-sg"
  })
}

resource "aws_security_group" "load_balancer" {
  name        = "${var.cluster_name}-alb"
  description = "Public ingress to the Kubernetes ingress controller"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.tls_certificate_arn == null ? [] : [1]

    content {
      description = "HTTPS from the internet"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-lb-sg"
  })
}

resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster"
  description = "Cluster node access and east-west traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description = "Kubernetes API from admin CIDR"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_source_cidr]
  }

  ingress {
    description     = "Kubernetes API from bastion"
    from_port       = 6443
    to_port         = 6443
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description     = "Ingress HTTP NodePort from ALB"
    from_port       = var.ingress_http_nodeport
    to_port         = var.ingress_http_nodeport
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer.id]
  }

  ingress {
    description     = "Ingress HTTPS NodePort from ALB"
    from_port       = var.ingress_https_nodeport
    to_port         = var.ingress_https_nodeport
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer.id]
  }

  ingress {
    description     = "Headlamp NodePort from bastion"
    from_port       = var.headlamp_nodeport
    to_port         = var.headlamp_nodeport
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description = "All traffic between cluster nodes"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-cluster-sg"
  })
}

resource "aws_key_pair" "main" {
  key_name   = "${var.cluster_name}-${var.ssh_user}"
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-key"
  })
}

resource "aws_instance" "bastion" {
  ami                         = var.ami_id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.subnets["public-a"].id
  key_name                    = aws_key_pair.main.key_name
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-bastion"
    Role = "bastion"
  })
}

resource "aws_instance" "nodes" {
  for_each = local.nodes

  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.subnets[each.value.subnet_key].id
  private_ip                  = each.value.private_ip
  key_name                    = aws_key_pair.main.key_name
  vpc_security_group_ids      = [aws_security_group.cluster.id]
  associate_public_ip_address = false
  user_data                   = local.kubespray_bootstrap_script
  user_data_replace_on_change = true

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-${each.key}"
    Role = each.value.role
  })
}

resource "aws_lb" "ingress" {
  name               = substr(replace("${var.cluster_name}-ingress", "_", "-"), 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.load_balancer.id]
  subnets = [
    aws_subnet.subnets["public-a"].id,
    aws_subnet.subnets["public-b"].id,
  ]

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-ingress"
  })
}

resource "aws_lb_target_group" "ingress_http" {
  name        = substr(replace("${var.cluster_name}-http", "_", "-"), 0, 32)
  port        = var.ingress_http_nodeport
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 15
    timeout             = 5
    protocol            = "HTTP"
    path                = "/"
    matcher             = "200-499"
    port                = tostring(var.ingress_http_nodeport)
  }

  tags = merge(local.common_tags, {
    Name = "${var.cluster_name}-http-tg"
  })
}

resource "aws_lb_target_group_attachment" "ingress_http" {
  for_each = aws_instance.nodes

  target_group_arn = aws_lb_target_group.ingress_http.arn
  target_id        = each.value.id
  port             = var.ingress_http_nodeport
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.ingress.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_http.arn
  }
}

resource "aws_lb_listener" "https" {
  count = var.tls_certificate_arn == null ? 0 : 1

  load_balancer_arn = aws_lb.ingress.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.tls_certificate_arn
  ssl_policy        = "ELBSecurityPolicy-2016-08"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingress_http.arn
  }
}
