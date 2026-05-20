locals {
  name           = "${var.stack.name_prefix}-ui"
  instance_type  = var.stack.instances[var.stack.app_names[0]].aws_instance_type
  image_key      = try(var.stack.defaults.image, "ubuntu_2204")
  domain_enabled = try(var.stack.domain.enabled, false) && try(var.stack.ui.domain, "") != ""
  create_dns     = local.domain_enabled && try(var.stack.domain.create_records, true)
  domain_name    = try(var.stack.ui.domain, "")

  user_data = <<-EOT
  #cloud-config
  users:
    - name: ${var.stack.ssh.user}
      groups: [sudo]
      shell: /bin/bash
      sudo: ['ALL=(ALL) NOPASSWD:ALL']
      ssh_authorized_keys:
        - ${var.stack.ssh_public_key}
  package_update: true
  packages:
    - python3
  EOT

  ssh_config = <<-EOT
  Host ${local.name}
    HostName ${aws_instance.ui.public_ip}
    User ${var.stack.ssh.user}
    IdentityFile ${var.stack.ssh.private_key_path}
    IdentitiesOnly yes
    UserKnownHostsFile ${var.known_hosts_file}
    StrictHostKeyChecking accept-new
  EOT

  ansible_inventory = <<-EOT

  [ui]
  ${local.name} ansible_host=${aws_instance.ui.public_ip}

  [cloud:children]
  ui

  [ui:vars]
  coinops_ssh_common_args='-o UserKnownHostsFile=${var.known_hosts_file} -o StrictHostKeyChecking=accept-new'
  EOT
}

data "aws_ami" "selected" {
  most_recent = true
  owners      = var.stack.image_catalog[local.image_key].aws.owners

  filter {
    name   = "name"
    values = [var.stack.image_catalog[local.image_key].aws.name_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "this" {
  cidr_block           = cidrsubnet(var.stack.network.cidr, 4, 4)
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name}-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.stack.network.cidr, 8, 64)
  availability_zone       = var.stack.aws.availability_zones[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public"
    Tier = "public"
  }
}

resource "aws_subnet" "public_lb" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.stack.network.cidr, 8, 65)
  availability_zone       = var.stack.aws.availability_zones[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name}-public-lb"
    Tier = "public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name}-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_lb" {
  subnet_id      = aws_subnet.public_lb.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "lb" {
  name        = "${local.name}-lb-sg"
  description = "Public web access to UI load balancer"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from web"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    cidr_blocks = try(var.stack.firewall.web_source_ranges, ["0.0.0.0/0"])
  }

  ingress {
    description = "HTTP redirect"
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = try(var.stack.firewall.web_source_ranges, ["0.0.0.0/0"])
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-lb-sg"
  }
}

resource "aws_security_group" "ui" {
  name        = "${local.name}-sg"
  description = "UI-only frontend host"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTP from UI ALB"
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    security_groups = [aws_security_group.lb.id]
  }

  dynamic "ingress" {
    for_each = try(var.stack.firewall.ssh_source_ranges, [])

    content {
      description = "SSH from operator"
      protocol    = "tcp"
      from_port   = 22
      to_port     = 22
      cidr_blocks = [ingress.value]
    }
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-sg"
  }
}

resource "aws_lb" "ui" {
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]
  subnets            = [aws_subnet.public.id, aws_subnet.public_lb.id]

  tags = {
    Name = "${local.name}-alb"
  }
}

resource "aws_lb_target_group" "ui" {
  name     = "${local.name}-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    enabled             = true
    path                = try(var.stack.app.health_path, "/health")
    matcher             = "200-399"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = {
    Name = "${local.name}-tg"
  }
}

resource "aws_lb_target_group_attachment" "ui" {
  target_group_arn = aws_lb_target_group.ui.arn
  target_id        = aws_instance.ui.id
  port             = 80
}

resource "aws_acm_certificate" "ui" {
  count = local.domain_enabled ? 1 : 0

  domain_name       = local.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name}-cert"
  }
}

locals {
  certificate_validation_records = local.domain_enabled ? {
    (local.domain_name) = {
      name    = one(aws_acm_certificate.ui[0].domain_validation_options).resource_record_name
      type    = one(aws_acm_certificate.ui[0].domain_validation_options).resource_record_type
      content = one(aws_acm_certificate.ui[0].domain_validation_options).resource_record_value
    }
  } : {}
}

resource "cloudflare_dns_record" "cert_validation" {
  for_each = local.create_dns ? local.certificate_validation_records : {}

  zone_id = var.stack.domain.cloudflare_zone_id
  name    = each.value.name
  type    = each.value.type
  content = each.value.content
  ttl     = 60
  proxied = false
}

resource "aws_acm_certificate_validation" "ui" {
  count = local.domain_enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.ui[0].arn
  validation_record_fqdns = local.create_dns ? [for record in cloudflare_dns_record.cert_validation : record.name] : []
}

resource "aws_lb_listener" "https" {
  count = local.domain_enabled ? 1 : 0

  load_balancer_arn = aws_lb.ui.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.ui[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ui.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  count = local.domain_enabled ? 1 : 0

  load_balancer_arn = aws_lb.ui.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "http_fallback" {
  count = local.domain_enabled ? 0 : 1

  load_balancer_arn = aws_lb.ui.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ui.arn
  }
}

resource "aws_key_pair" "ui" {
  key_name   = "${local.name}-key"
  public_key = var.stack.ssh_public_key
}

resource "aws_instance" "ui" {
  ami                         = data.aws_ami.selected.id
  instance_type               = local.instance_type
  subnet_id                   = aws_subnet.public.id
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.ui.id]
  key_name                    = aws_key_pair.ui.key_name
  user_data                   = local.user_data

  root_block_device {
    volume_size = try(var.stack.defaults.disk_size_gb, 10)
    volume_type = "gp3"
  }

  tags = {
    Name = local.name
    Role = "ui"
  }
}
