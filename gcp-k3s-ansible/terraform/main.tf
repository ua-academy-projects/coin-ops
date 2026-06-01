locals {
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))

  common_labels = merge(
    {
      project = replace(var.cluster_name, "_", "-")
      managed = "terraform"
      stack   = "k3s"
    },
    var.tags,
  )

  metadata_ssh_keys = "${var.ssh_user}:${local.ssh_public_key}"

  detected_allowed_source_cidr = "${trimspace(var.allowed_source_cidr != null && trimspace(var.allowed_source_cidr) != "" ? var.allowed_source_cidr : data.http.client_ip.response_body)}/32"

  nodes = {
    cp-1 = {
      private_ip = var.node_private_ips.cp_1
    }
    cp-2 = {
      private_ip = var.node_private_ips.cp_2
    }
    cp-3 = {
      private_ip = var.node_private_ips.cp_3
    }
  }

  ansible_inventory_ini = <<-EOT
    [all]
    cp-1 ansible_host=${google_compute_instance.nodes["cp-1"].network_interface[0].network_ip} ip=${google_compute_instance.nodes["cp-1"].network_interface[0].network_ip} access_ip=${google_compute_instance.nodes["cp-1"].network_interface[0].network_ip}
    cp-2 ansible_host=${google_compute_instance.nodes["cp-2"].network_interface[0].network_ip} ip=${google_compute_instance.nodes["cp-2"].network_interface[0].network_ip} access_ip=${google_compute_instance.nodes["cp-2"].network_interface[0].network_ip}
    cp-3 ansible_host=${google_compute_instance.nodes["cp-3"].network_interface[0].network_ip} ip=${google_compute_instance.nodes["cp-3"].network_interface[0].network_ip} access_ip=${google_compute_instance.nodes["cp-3"].network_interface[0].network_ip}

    [k3s_servers]
    cp-1
    cp-2
    cp-3

    [k3s_cluster:children]
    k3s_servers

    [all:vars]
    ansible_user=${var.ssh_user}
    ansible_ssh_private_key_file=~/.ssh/id_rsa
    ansible_ssh_common_args='-o ProxyJump=${var.ssh_user}@${google_compute_instance.bastion.network_interface[0].access_config[0].nat_ip} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
  EOT
}

data "http" "client_ip" {
  url = "https://api.ipify.org"

  request_headers = {
    Accept = "text/plain"
  }
}

resource "google_compute_network" "main" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "main" {
  name          = var.subnet_name
  ip_cidr_range = var.subnet_cidr
  region        = var.region
  network       = google_compute_network.main.id
}

resource "google_compute_router" "main" {
  name    = "${var.cluster_name}-router"
  region  = var.region
  network = google_compute_network.main.id
}

resource "google_compute_router_nat" "main" {
  name                               = "${var.cluster_name}-nat"
  router                             = google_compute_router.main.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.main.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

resource "google_compute_firewall" "bastion_ssh" {
  name    = "${var.cluster_name}-bastion-ssh"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [local.detected_allowed_source_cidr]
  target_tags   = ["${var.cluster_name}-bastion"]
}

resource "google_compute_firewall" "private_ssh_from_bastion" {
  name    = "${var.cluster_name}-private-ssh"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_tags = ["${var.cluster_name}-bastion"]
  target_tags = ["${var.cluster_name}-control-plane"]
}

resource "google_compute_firewall" "k3s_api_from_admin" {
  name    = "${var.cluster_name}-k3s-api-admin"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }

  source_ranges = [local.detected_allowed_source_cidr]
  target_tags   = ["${var.cluster_name}-control-plane"]
}

resource "google_compute_firewall" "k3s_api_from_bastion" {
  name    = "${var.cluster_name}-k3s-api-bastion"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["6443"]
  }

  source_tags = ["${var.cluster_name}-bastion"]
  target_tags = ["${var.cluster_name}-control-plane"]
}

resource "google_compute_firewall" "nodeports_from_admin" {
  name    = "${var.cluster_name}-nodeports-admin"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["30000-32767"]
  }

  source_ranges = [local.detected_allowed_source_cidr]
  target_tags   = ["${var.cluster_name}-control-plane"]
}

resource "google_compute_firewall" "traefik_backends" {
  name    = "${var.cluster_name}-traefik-backends"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports = [
      tostring(var.traefik_http_nodeport),
      tostring(var.traefik_https_nodeport),
    ]
  }

  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = ["${var.cluster_name}-control-plane"]
}

resource "google_compute_firewall" "internal" {
  name    = "${var.cluster_name}-internal"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["1-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["1-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = ["${var.cluster_name}-control-plane", "${var.cluster_name}-bastion"]
}

resource "google_compute_instance" "bastion" {
  name         = "${var.cluster_name}-bastion"
  machine_type = var.bastion_machine_type
  zone         = var.zone
  tags         = ["${var.cluster_name}-bastion"]

  boot_disk {
    initialize_params {
      image = var.image
      size  = 20
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id
    network_ip = var.bastion_private_ip

    access_config {}
  }

  metadata = {
    ssh-keys = local.metadata_ssh_keys
  }

  labels = local.common_labels
}

resource "google_compute_instance" "nodes" {
  for_each = local.nodes

  name         = "${var.cluster_name}-${each.key}"
  machine_type = var.node_machine_type
  zone         = var.zone
  tags         = ["${var.cluster_name}-control-plane"]

  boot_disk {
    initialize_params {
      image = var.image
      size  = 30
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.main.id
    network_ip = each.value.private_ip
  }

  metadata = {
    ssh-keys = local.metadata_ssh_keys
  }

  labels = merge(local.common_labels, {
    node = replace(each.key, "_", "-")
  })
}

resource "google_compute_instance_group" "traefik_backends" {
  name      = "${var.cluster_name}-traefik-backends"
  zone      = var.zone
  instances = [for instance in google_compute_instance.nodes : instance.self_link]

  named_port {
    name = "traefik-http"
    port = var.traefik_http_nodeport
  }

  named_port {
    name = "traefik-https"
    port = var.traefik_https_nodeport
  }
}

resource "google_compute_health_check" "traefik_http" {
  name               = "${var.cluster_name}-traefik-http"
  check_interval_sec = 10
  timeout_sec        = 5

  tcp_health_check {
    port = var.traefik_http_nodeport
  }
}

resource "google_compute_health_check" "traefik_https" {
  name               = "${var.cluster_name}-traefik-https"
  check_interval_sec = 10
  timeout_sec        = 5

  tcp_health_check {
    port = var.traefik_https_nodeport
  }
}

resource "google_compute_global_address" "traefik_public_ip" {
  name = "${var.cluster_name}-traefik-public-ip"
}

resource "google_compute_backend_service" "traefik_http" {
  name                  = "${var.cluster_name}-traefik-http"
  protocol              = "TCP"
  port_name             = "traefik-http"
  timeout_sec           = 10
  load_balancing_scheme = "EXTERNAL_MANAGED"
  health_checks         = [google_compute_health_check.traefik_http.id]

  backend {
    group = google_compute_instance_group.traefik_backends.id
  }
}

resource "google_compute_backend_service" "traefik_https" {
  name                  = "${var.cluster_name}-traefik-https"
  protocol              = "TCP"
  port_name             = "traefik-https"
  timeout_sec           = 10
  load_balancing_scheme = "EXTERNAL_MANAGED"
  health_checks         = [google_compute_health_check.traefik_https.id]

  backend {
    group = google_compute_instance_group.traefik_backends.id
  }
}

resource "google_compute_target_tcp_proxy" "traefik_http" {
  name            = "${var.cluster_name}-traefik-http"
  backend_service = google_compute_backend_service.traefik_http.id
  proxy_header    = "NONE"
}

resource "google_compute_target_tcp_proxy" "traefik_https" {
  name            = "${var.cluster_name}-traefik-https"
  backend_service = google_compute_backend_service.traefik_https.id
  proxy_header    = "NONE"
}

resource "google_compute_global_forwarding_rule" "traefik_http" {
  name                  = "${var.cluster_name}-traefik-http"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.traefik_public_ip.address
  port_range            = "80"
  target                = google_compute_target_tcp_proxy.traefik_http.id
}

resource "google_compute_global_forwarding_rule" "traefik_https" {
  name                  = "${var.cluster_name}-traefik-https"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.traefik_public_ip.address
  port_range            = "443"
  target                = google_compute_target_tcp_proxy.traefik_https.id
}

resource "local_file" "ansible_inventory" {
  filename = abspath("${path.module}/${var.ansible_inventory_path}")
  content  = local.ansible_inventory_ini
}
