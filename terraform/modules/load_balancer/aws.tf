# ═════════════════════════════════════════════════════════════════════════════
# AWS LOAD BALANCER (Application Load Balancer)
# ═════════════════════════════════════════════════════════════════════════════

# ─── Load Balancer Security Group ────────────────────────────────────────────
resource "aws_security_group" "lb_sg" {
  count       = var.cloud_provider == "aws" ? 1 : 0
  name        = "${var.name}-lb-sg"
  description = "Security group for ${var.name} load balancer"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.listeners
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
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

  tags = merge(var.common_tags, { Name = "${var.name}-lb-sg" })
}

# ─── Load Balancer ───────────────────────────────────────────────────────────
resource "aws_lb" "this" {
  count              = var.cloud_provider == "aws" ? 1 : 0
  name               = var.name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg[0].id]
  # ALB requires at least two subnets in different AZs. We pass all subnets where our backends live.
  subnets = distinct([for b in var.backends : var.subnet_ids[b.subnet_name]])

  tags = merge(var.common_tags, { Name = var.name })
}

# ─── Target Group ────────────────────────────────────────────────────────────
resource "aws_lb_target_group" "this" {
  count    = var.cloud_provider == "aws" ? 1 : 0
  name     = "${var.name}-tg"
  port     = values(var.backends)[0].port # Assuming all backends share the same port
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    protocol            = var.health_check.protocol
    port                = var.health_check.port
    path                = var.health_check.path
    interval            = var.health_check.interval_sec
    timeout             = var.health_check.timeout_sec
    healthy_threshold   = var.health_check.healthy_threshold
    unhealthy_threshold = var.health_check.unhealthy_threshold
  }

  tags = merge(var.common_tags, { Name = "${var.name}-tg" })
}

# ─── ACM Certificate ─────────────────────────────────────────────────────────
resource "aws_acm_certificate" "this" {
  count = var.cloud_provider == "aws" && length(var.domains) > 0 ? 1 : 0

  domain_name               = var.domains[0]
  subject_alternative_names = length(var.domains) > 1 ? slice(var.domains, 1, length(var.domains)) : []
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, { Name = "${var.name}-cert" })
}

# ─── Listeners ───────────────────────────────────────────────────────────────
resource "aws_lb_listener" "this" {
  for_each = var.cloud_provider == "aws" ? var.listeners : {}

  load_balancer_arn = aws_lb.this[0].arn
  port              = each.value.port
  protocol          = each.value.protocol

  certificate_arn = upper(each.value.protocol) == "HTTPS" && length(var.domains) > 0 ? aws_acm_certificate.this[0].arn : null

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[0].arn
  }
}

# ─── Target Group Attachments ────────────────────────────────────────────────
resource "aws_lb_target_group_attachment" "this" {
  for_each = var.cloud_provider == "aws" ? var.backends : {}

  target_group_arn = aws_lb_target_group.this[0].arn
  target_id        = var.instance_ids[each.key]
  port             = each.value.port
}
