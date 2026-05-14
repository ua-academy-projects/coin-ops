locals {
  cloud       = lower(var.cloud)
  gcp_enabled = local.cloud == "gcp"
  aws_enabled = local.cloud == "aws"
}

resource "google_compute_firewall" "allow_ssh_to_bastion" {
  count   = local.gcp_enabled ? 1 : 0
  name    = "allow-ssh-to-bastion"
  network = var.network_name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [var.allowed_source_cidr]
  target_tags   = var.bastion_tags
}

resource "google_compute_firewall" "allow_ssh_from_bastion" {
  count   = local.gcp_enabled ? 1 : 0
  name    = "allow-ssh-from-bastion"
  network = var.network_name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_tags = var.bastion_tags
  target_tags = var.private_target_tags
}

resource "google_compute_firewall" "allow_http_to_web" {
  count   = local.gcp_enabled ? 1 : 0
  name    = "allow-http-to-web"
  network = var.network_name

  allow {
    protocol = "tcp"
    ports    = [tostring(var.load_balancer_port)]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = var.web_target_tags
}

resource "google_compute_firewall" "allow_private_service_traffic" {
  count   = local.gcp_enabled ? 1 : 0
  name    = "allow-private-service-traffic"
  network = var.network_name

  allow {
    protocol = "tcp"
    ports    = ["5432", "8000", "8080", "5672"]
  }

  source_tags = var.private_target_tags
  target_tags = var.private_target_tags
}

resource "aws_security_group" "load_balancer" {
  count       = local.aws_enabled ? 1 : 0
  name        = "${var.network_name}-load-balancer"
  description = "Allow HTTP to load balancer."
  vpc_id      = var.vpc_id

  ingress {
    from_port   = var.load_balancer_port
    to_port     = var.load_balancer_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "bastion" {
  count       = local.aws_enabled ? 1 : 0
  name        = "${var.network_name}-bastion"
  description = "Allow SSH to bastion from admin CIDR."
  vpc_id      = var.vpc_id

  ingress {
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
}

resource "aws_security_group" "private" {
  count       = local.aws_enabled ? 1 : 0
  name        = "${var.network_name}-private"
  description = "Allow SSH from bastion and east-west service traffic between private VMs."
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.private_service_cidr]
  }

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = [var.private_service_cidr]
  }

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.private_service_cidr]
  }

  ingress {
    from_port   = 5672
    to_port     = 5672
    protocol    = "tcp"
    cidr_blocks = [var.private_service_cidr]
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion[0].id]
  }

  ingress {
    from_port       = var.load_balancer_port
    to_port         = var.load_balancer_port
    protocol        = "tcp"
    security_groups = [aws_security_group.load_balancer[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
