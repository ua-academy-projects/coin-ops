locals {
  config       = var.config
  name_prefix  = local.config.name_prefix
  ssh          = local.config.ssh
  network_key  = local.config.defaults.network
  network      = local.config.networks[local.network_key]
  aws_location = local.config.catalog.locations[local.config.location].aws
  azs          = local.aws_location.availability_zones

  public_subnet_cidrs  = local.network.public_subnet_cidrs
  private_subnet_cidrs = local.network.private_subnet_cidrs

  public_subnets = {
    for idx, cidr in local.public_subnet_cidrs : tostring(idx) => {
      cidr = cidr
      az   = local.azs[idx % length(local.azs)]
    }
  }

  private_subnets = {
    for idx, cidr in local.private_subnet_cidrs : tostring(idx) => {
      cidr = cidr
      az   = local.azs[idx % length(local.azs)]
    }
  }

  instances     = local.config.instances
  app_names     = local.config.app.nodes.app
  db_name       = local.config.app.nodes.db
  bastion_name  = local.config.app.nodes.bastion
  app_instances = { for name, inst in local.instances : name => inst if contains(local.app_names, name) }
  db_instances  = { for name, inst in local.instances : name => inst if name == local.db_name }
  bastions      = { for name, inst in local.instances : name => inst if name == local.bastion_name }

  default_size_key  = local.config.defaults.size
  default_image_key = local.config.defaults.image
  image_catalog     = { for image_key, image_config in local.config.catalog.images : image_key => image_config.aws }

  domain_enabled = try(local.config.domain.enabled, false)
  create_dns     = local.domain_enabled && try(local.config.domain.create_records, true)
  app_port       = local.config.app.port
  health_path    = local.config.app.health_path

  ssh_public_key = trimspace(file(pathexpand(local.ssh.public_key_path)))

  user_data = <<-EOT
  #cloud-config
  users:
    - name: ${local.ssh.user}
      groups: [sudo]
      shell: /bin/bash
      sudo: ['ALL=(ALL) NOPASSWD:ALL']
      ssh_authorized_keys:
        - ${local.ssh_public_key}
  package_update: true
  packages:
    - python3
  EOT
}

data "aws_ami" "selected" {
  for_each = local.image_catalog

  most_recent = true
  owners      = each.value.owners

  filter {
    name   = "name"
    values = [each.value.name_filter]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "this" {
  cidr_block           = local.network.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = local.network.name
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-${each.key}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-private-${each.key}"
    Tier = "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip"
  }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["0"].id

  tags = {
    Name = "${local.name_prefix}-nat"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-private-rt"
  }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this.id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "bastion" {
  name        = "${local.name_prefix}-bastion-sg"
  description = "SSH admin access to bastion"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH from allowed operator CIDRs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = local.config.firewall.ssh_source_ranges
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-bastion-sg" }
}

resource "aws_security_group" "lb" {
  name        = "${local.name_prefix}-web-lb-sg"
  description = "Public web access to load balancer"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTPS from web"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = local.config.firewall.web_source_ranges
  }

  ingress {
    description = "HTTP fallback or redirect"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = local.config.firewall.web_source_ranges
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-web-lb-sg" }
}

resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app-sg"
  description = "App instances behind load balancer"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = local.app_port
    to_port         = local.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.lb.id]
  }

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-app-sg" }
}

resource "aws_security_group" "db" {
  name        = "${local.name_prefix}-db-sg"
  description = "Private DB/runtime services"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "SSH from bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]
  }

  ingress {
    description     = "PostgreSQL from app"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "RabbitMQ from app"
    from_port       = 5672
    to_port         = 5672
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  ingress {
    description     = "Redis from app"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  dynamic "ingress" {
    for_each = local.config.firewall.allow_icmp_from_bastion ? [1] : []
    content {
      description     = "ICMP from bastion"
      from_port       = -1
      to_port         = -1
      protocol        = "icmp"
      security_groups = [aws_security_group.bastion.id]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-db-sg" }
}

resource "aws_key_pair" "lab" {
  key_name   = "${local.name_prefix}-key"
  public_key = local.ssh_public_key
}

resource "aws_instance" "bastion" {
  for_each = local.bastions

  ami                         = data.aws_ami.selected[lookup(each.value, "image", local.default_image_key)].id
  instance_type               = local.config.catalog.sizes[lookup(each.value, "size", local.default_size_key)].aws
  subnet_id                   = aws_subnet.public["0"].id
  private_ip                  = each.value.private_ip
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  key_name                    = aws_key_pair.lab.key_name
  user_data                   = local.user_data

  root_block_device {
    volume_size = lookup(each.value, "disk_size_gb", local.config.defaults.disk_size_gb)
    volume_type = "gp3"
  }

  tags = {
    Name = "${local.name_prefix}-${each.key}"
    Role = "bastion"
  }
}

resource "aws_instance" "app" {
  for_each = local.app_instances

  ami                         = data.aws_ami.selected[lookup(each.value, "image", local.default_image_key)].id
  instance_type               = local.config.catalog.sizes[lookup(each.value, "size", local.default_size_key)].aws
  subnet_id                   = values(aws_subnet.private)[index(local.app_names, each.key) % length(values(aws_subnet.private))].id
  private_ip                  = each.value.private_ip
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.app.id]
  key_name                    = aws_key_pair.lab.key_name
  user_data                   = local.user_data

  root_block_device {
    volume_size = lookup(each.value, "disk_size_gb", local.config.defaults.disk_size_gb)
    volume_type = "gp3"
  }

  tags = {
    Name = "${local.name_prefix}-${each.key}"
    Role = "app"
  }
}

resource "aws_instance" "db" {
  for_each = local.db_instances

  ami                         = data.aws_ami.selected[lookup(each.value, "image", local.default_image_key)].id
  instance_type               = local.config.catalog.sizes[lookup(each.value, "size", local.default_size_key)].aws
  subnet_id                   = aws_subnet.private["0"].id
  private_ip                  = each.value.private_ip
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.db.id]
  key_name                    = aws_key_pair.lab.key_name
  user_data                   = local.user_data

  root_block_device {
    volume_size = lookup(each.value, "disk_size_gb", local.config.defaults.disk_size_gb)
    volume_type = "gp3"
  }

  tags = {
    Name = "${local.name_prefix}-${each.key}"
    Role = "db"
  }
}

resource "aws_lb" "app" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  tags = { Name = "${local.name_prefix}-alb" }
}

resource "aws_lb_target_group" "app" {
  name     = "${local.name_prefix}-app-tg"
  port     = local.app_port
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  health_check {
    enabled             = true
    path                = local.health_path
    matcher             = "200-399"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = { Name = "${local.name_prefix}-app-tg" }
}

resource "aws_lb_target_group_attachment" "app" {
  for_each = aws_instance.app

  target_group_arn = aws_lb_target_group.app.arn
  target_id        = each.value.id
  port             = local.app_port
}

resource "aws_acm_certificate" "app" {
  count = local.domain_enabled ? 1 : 0

  domain_name       = local.config.domain.name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = { Name = "${local.name_prefix}-cert" }
}

locals {
  certificate_validation_records = local.domain_enabled ? {
    for dvo in aws_acm_certificate.app[0].domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      type    = dvo.resource_record_type
      content = dvo.resource_record_value
    }
  } : {}
}

resource "cloudflare_dns_record" "cert_validation" {
  for_each = local.create_dns ? local.certificate_validation_records : {}

  zone_id = local.config.domain.cloudflare_zone_id
  name    = each.value.name
  type    = each.value.type
  content = each.value.content
  ttl     = 60
  proxied = false
}

resource "aws_acm_certificate_validation" "app" {
  count = local.domain_enabled ? 1 : 0

  certificate_arn         = aws_acm_certificate.app[0].arn
  validation_record_fqdns = local.create_dns ? [for record in cloudflare_dns_record.cert_validation : record.name] : []
}

resource "aws_lb_listener" "https" {
  count = local.domain_enabled ? 1 : 0

  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.app[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  count = local.domain_enabled ? 1 : 0

  load_balancer_arn = aws_lb.app.arn
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

  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "cloudflare_dns_record" "app" {
  count = local.create_dns ? 1 : 0

  zone_id = local.config.domain.cloudflare_zone_id
  name    = local.config.domain.name
  type    = "CNAME"
  content = aws_lb.app.dns_name
  ttl     = 60
  proxied = false
}
