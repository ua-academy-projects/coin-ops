locals {
  cloud       = lower(var.cloud)
  gcp_enabled = local.cloud == "gcp"
  aws_enabled = local.cloud == "aws"
}

resource "google_compute_http_health_check" "web" {
  count              = local.gcp_enabled ? 1 : 0
  name               = "${var.name}-web-health-check"
  port               = var.port
  request_path       = "/"
  check_interval_sec = 10
  timeout_sec        = 5
}

resource "google_compute_target_pool" "web" {
  count     = local.gcp_enabled ? 1 : 0
  name      = "${var.name}-web-target-pool"
  region    = var.gcp_region
  instances = [var.gcp_target_self_link]
  health_checks = [
    google_compute_http_health_check.web[0].self_link
  ]
}

resource "google_compute_forwarding_rule" "web" {
  count       = local.gcp_enabled ? 1 : 0
  name        = "${var.name}-web-lb"
  region      = var.gcp_region
  target      = google_compute_target_pool.web[0].self_link
  port_range  = tostring(var.port)
  ip_protocol = "TCP"
}

resource "aws_elb" "web" {
  count           = local.aws_enabled ? 1 : 0
  name            = "${var.name}-web-lb"
  subnets         = var.aws_public_subnet_ids
  security_groups = [var.aws_security_group_id]
  instances       = [var.aws_target_instance_id]

  listener {
    instance_port     = var.port
    instance_protocol = "http"
    lb_port           = var.port
    lb_protocol       = "http"
  }

  health_check {
    target              = "HTTP:${var.port}/"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }

  tags = {
    Name = "${var.name}-web-lb"
  }
}
