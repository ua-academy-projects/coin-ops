# aws_lb/main.tf
# Application Load Balancer for k3s cluster.
# ALB routes HTTP/HTTPS traffic across all three k3s nodes.
# Traefik on each node handles TLS termination and routing by domain.
#
# Architecture:
#   Internet → ALB (ports 80/443) → Target Group → k3s nodes → Traefik

locals {
  create = var.config.general.cloud == "aws" ? 1 : 0
}

# Security Group for ALB — allow HTTP and HTTPS from internet
resource "aws_security_group" "alb" {
  count       = local.create
  name        = "alb-sg"
  description = "Allow HTTP and HTTPS from internet to ALB"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "alb-sg" }
}

# ALB — public, spans two availability zones (AWS requirement)
resource "aws_lb" "main" {
  count              = local.create
  name               = "coinops-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]

  # ALB requires minimum 2 subnets in different AZs
  subnets = [
    var.public_subnet_id,
    var.public_subnet_b_id
  ]

  tags = { Name = "coinops-alb" }
}

# Target Group — all three k3s nodes on port 80 (Traefik HTTP)
resource "aws_lb_target_group" "k3s" {
  count    = local.create
  name     = "coinops-k3s"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  # Health check — TCP on port 80, same as GCP health check
  health_check {
    protocol            = "TCP"
    port                = "80"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
}

  tags = { Name = "coinops-k3s-tg" }
}

# Register all k3s nodes in Target Group
resource "aws_lb_target_group_attachment" "k3s" {
  for_each = local.create == 1 ? var.k3s_instance_ids : {}

  target_group_arn = aws_lb_target_group.k3s[0].arn
  target_id        = each.value
  port             = 80
}

# Listener port 80 — forward to k3s Target Group
resource "aws_lb_listener" "http" {
  count             = local.create
  load_balancer_arn = aws_lb.main[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k3s[0].arn
  }
}

# Listener port 443 — forward to k3s Target Group (Traefik handles TLS)
resource "aws_lb_listener" "https" {
  count             = local.create
  load_balancer_arn = aws_lb.main[0].arn
  port              = 443
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k3s[0].arn
  }
}