# ============================================================================
# GCP RESOURCES (active when var.cloud == "gcp")
# ============================================================================

resource "google_compute_project_metadata" "ssh_keys" {
  count = var.cloud == "gcp" ? 1 : 0

  metadata = {
    ssh-keys = "${local.general.ssh_user}:${var.ssh_public_key}"
  }
}

resource "google_project_service" "gcp_services" {
  for_each = var.cloud == "gcp" ? toset([
    "secretmanager.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com"
  ]) : toset([])

  project            = local.general.providers.gcp.project_id
  service            = each.key
  disable_on_destroy = false
}

module "network_gcp" {
  source   = "../../modules/gcp/network"
  for_each = { for name, network in local.networks : name => network if var.cloud == "gcp" }

  project_id  = local.general.providers.gcp.project_id
  name        = each.key
  description = lookup(each.value, "description", "")

  subnets = {
    for subnet_name, subnet in local.subnets :
    subnet_name => {
      cidr   = subnet.cidr
      region = local.general.providers.gcp.region
    }
    if subnet.network == each.key
  }
}

resource "google_compute_router" "nat_gcp" {
  for_each = var.cloud == "gcp" ? local.networks : {}

  project = local.general.providers.gcp.project_id
  name    = "${each.key}-nat-router"
  region  = local.general.providers.gcp.region
  network = module.network_gcp[each.key].network_self_link
}

resource "google_compute_router_nat" "nat_gcp" {
  for_each = google_compute_router.nat_gcp

  project = local.general.providers.gcp.project_id
  name    = "${each.key}-nat"
  router  = each.value.name
  region  = each.value.region

  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

resource "google_compute_global_address" "private_services" {
  count = var.cloud == "gcp" ? 1 : 0

  project       = local.general.providers.gcp.project_id
  name          = "coinops-private-services-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = module.network_gcp["terraform-network"].network_self_link

  depends_on = [google_project_service.gcp_services]
}

resource "google_service_networking_connection" "private_services" {
  count = var.cloud == "gcp" ? 1 : 0

  network                 = module.network_gcp["terraform-network"].network_self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_services[0].name]

  depends_on = [google_project_service.gcp_services]
}

resource "google_sql_database_instance" "postgres" {
  count = var.cloud == "gcp" ? 1 : 0

  project             = local.general.providers.gcp.project_id
  name                = var.cloud_sql_instance_name
  database_version    = "POSTGRES_16"
  region              = local.general.providers.gcp.region
  deletion_protection = false

  settings {
    tier              = "db-f1-micro"
    availability_type = "ZONAL"
    disk_size         = local.general.default_disk_size_gb
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    backup_configuration {
      enabled                        = true
      point_in_time_recovery_enabled = true
    }

    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = module.network_gcp["terraform-network"].network_self_link
      enable_private_path_for_google_cloud_services = true
    }
  }

  depends_on = [google_service_networking_connection.private_services]

  lifecycle {
    prevent_destroy = false
  }
}

resource "google_sql_database" "app" {
  count = var.cloud == "gcp" ? 1 : 0

  project  = local.general.providers.gcp.project_id
  name     = var.cloud_sql_database_name
  instance = google_sql_database_instance.postgres[0].name
}

resource "google_secret_manager_secret" "db" {
  count = var.cloud == "gcp" ? 1 : 0

  project   = local.general.providers.gcp.project_id
  secret_id = var.db_secret_name

  replication {
    auto {}
  }

  depends_on = [google_project_service.gcp_services]
}

resource "google_secret_manager_secret" "services" {
  count = var.cloud == "gcp" ? 1 : 0

  project   = local.general.providers.gcp.project_id
  secret_id = var.service_secret_name

  replication {
    auto {}
  }

  depends_on = [google_project_service.gcp_services]
}


module "firewall_gcp" {
  source   = "../../modules/gcp/firewall"
  for_each = { for name, rule in local.firewall_rules : name => rule if var.cloud == "gcp" }

  project_id        = local.general.providers.gcp.project_id
  name              = each.key
  network_self_link = module.network_gcp[each.value.network].network_self_link

  protocol      = lookup(each.value, "protocol", null)
  protocols     = lookup(each.value, "protocols", [])
  ports         = lookup(each.value, "ports", [])
  source_ranges = lookup(each.value, "source_ranges", [])
  source_tags   = lookup(each.value, "source_tags", [])
  target_tags   = each.value.target_tags
  description   = each.value.description
}

module "vm_gcp" {
  source   = "../../modules/gcp/vm"
  for_each = { for name, vm in local.vms : name => vm if var.cloud == "gcp" }

  project_id     = local.general.providers.gcp.project_id
  name           = each.key
  zone           = local.general.providers.gcp.zone
  environment    = local.general.environment
  ssh_user       = local.general.ssh_user
  ssh_public_key = var.ssh_public_key
  ssh_port       = local.general.ssh_port

  machine_type = lookup(
    local.cloud_machine_types,
    lookup(each.value, "machine_type", local.general.default_machine_type),
    lookup(each.value, "machine_type", local.resolved_default_machine_type)
  )

  os_image = lookup(
    local.cloud_os_images,
    lookup(each.value, "os_image", local.general.default_os),
    lookup(each.value, "os_image", local.resolved_default_os)
  )

  disk_type = lookup(
    local.cloud_disk_types,
    lookup(each.value, "disk_type", local.general.default_disk_type),
    lookup(each.value, "disk_type", local.resolved_default_disk_type)
  )

  disk_size_gb = lookup(each.value, "disk_size_gb", local.general.default_disk_size_gb)

  network_self_link = module.network_gcp[each.value.network].network_self_link
  subnet_self_link  = module.network_gcp[each.value.network].subnet_self_links[each.value.subnet]

  assign_public_ip = lookup(each.value, "assign_public_ip", false)
  tags             = lookup(each.value, "tags", [])
  labels           = lookup(each.value, "labels", {})
}

resource "google_compute_firewall" "allow_gcp_lb_to_ui" {
  count = var.cloud == "gcp" ? 1 : 0

  project = local.general.providers.gcp.project_id
  name    = "allow-gcp-lb-to-ui"
  network = module.network_gcp["terraform-network"].network_self_link

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  source_ranges = [
    "35.191.0.0/16",
    "130.211.0.0/22"
  ]

  target_tags = ["internal-vm"]
  description = "Allow Google Cloud Load Balancer and health checks to reach UI backends"
}

resource "google_compute_global_address" "app_lb" {
  count = var.cloud == "gcp" ? 1 : 0

  project = local.general.providers.gcp.project_id
  name    = "coinops-app-lb-ip"
}

resource "google_compute_instance_group" "ui" {
  count = var.cloud == "gcp" ? 1 : 0

  project   = local.general.providers.gcp.project_id
  name      = "coinops-ui-instance-group"
  zone      = local.general.providers.gcp.zone
  instances = [module.vm_gcp["vm-3"].self_link]

  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_health_check" "ui" {
  count = var.cloud == "gcp" ? 1 : 0

  project = local.general.providers.gcp.project_id
  name    = "coinops-ui-health-check"

  http_health_check {
    port         = 80
    request_path = "/health"
  }
}

resource "google_compute_backend_service" "ui" {
  count = var.cloud == "gcp" ? 1 : 0

  project               = local.general.providers.gcp.project_id
  name                  = "coinops-ui-backend"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.ui[0].self_link]

  backend {
    group = google_compute_instance_group.ui[0].self_link
  }
}

resource "google_compute_url_map" "https" {
  count = var.cloud == "gcp" ? 1 : 0

  project         = local.general.providers.gcp.project_id
  name            = "coinops-https-url-map"
  default_service = google_compute_backend_service.ui[0].self_link
}

resource "google_compute_url_map" "http_redirect" {
  count = var.cloud == "gcp" ? 1 : 0

  project = local.general.providers.gcp.project_id
  name    = "coinops-http-redirect-url-map"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_managed_ssl_certificate" "app" {
  count = var.cloud == "gcp" ? 1 : 0

  project = local.general.providers.gcp.project_id
  name    = "coinops-managed-cert"

  managed {
    domains = [
      var.app_domain,
      "www.${var.app_domain}"
    ]
  }
}

resource "google_compute_target_https_proxy" "app" {
  count = var.cloud == "gcp" ? 1 : 0

  project          = local.general.providers.gcp.project_id
  name             = "coinops-https-proxy"
  url_map          = google_compute_url_map.https[0].self_link
  ssl_certificates = [google_compute_managed_ssl_certificate.app[0].self_link]
}

resource "google_compute_target_http_proxy" "redirect" {
  count = var.cloud == "gcp" ? 1 : 0

  project = local.general.providers.gcp.project_id
  name    = "coinops-http-redirect-proxy"
  url_map = google_compute_url_map.http_redirect[0].self_link
}

resource "google_compute_global_forwarding_rule" "https" {
  count = var.cloud == "gcp" ? 1 : 0

  project               = local.general.providers.gcp.project_id
  name                  = "coinops-https-forwarding-rule"
  ip_address            = google_compute_global_address.app_lb[0].address
  port_range            = "443"
  target                = google_compute_target_https_proxy.app[0].self_link
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

resource "google_compute_global_forwarding_rule" "http" {
  count = var.cloud == "gcp" ? 1 : 0

  project               = local.general.providers.gcp.project_id
  name                  = "coinops-http-forwarding-rule"
  ip_address            = google_compute_global_address.app_lb[0].address
  port_range            = "80"
  target                = google_compute_target_http_proxy.redirect[0].self_link
  load_balancing_scheme = "EXTERNAL_MANAGED"
}

# ============================================================================
# AWS RESOURCES (active when var.cloud == "aws")
# ============================================================================

resource "aws_key_pair" "this" {
  count = var.cloud == "aws" ? 1 : 0

  key_name   = "${local.general.environment}-ssh-key"
  public_key = var.ssh_public_key
}

module "network_aws" {
  source   = "../../modules/aws/network"
  for_each = { for name, network in local.networks : name => network if var.cloud == "aws" }

  name = each.key

  subnets = {
    for subnet_name, subnet in local.subnets :
    subnet_name => {
      cidr              = subnet.cidr
      availability_zone = local.aws_availability_zone
    }
    if subnet.network == each.key
  }
}

module "firewall_aws" {
  source   = "../../modules/aws/firewall"
  for_each = { for name, rule in local.firewall_rules : name => rule if var.cloud == "aws" }

  name        = each.key
  vpc_id      = module.network_aws[each.value.network].vpc_id
  description = each.value.description

  ingress_rules = flatten([
    for protocol in length(lookup(each.value, "protocols", [])) > 0 ? lookup(each.value, "protocols", []) : [lookup(each.value, "protocol", "tcp")] : [
      for port_range in lookup(each.value, "ports", ["0"]) : {
        protocol    = protocol == "all" ? "-1" : protocol
        from_port   = protocol == "icmp" ? -1 : protocol == "all" ? 0 : tonumber(split("-", port_range)[0])
        to_port     = protocol == "icmp" ? -1 : protocol == "all" ? 0 : length(split("-", port_range)) > 1 ? tonumber(split("-", port_range)[1]) : tonumber(split("-", port_range)[0])
        cidr_blocks = length(lookup(each.value, "source_ranges", [])) > 0 ? lookup(each.value, "source_ranges", []) : [for subnet in local.subnets : subnet.cidr if subnet.network == each.value.network]
        description = each.value.description
      }
    ]
  ])
}

module "vm_aws" {
  source   = "../../modules/aws/vm"
  for_each = { for name, vm in local.vms : name => vm if var.cloud == "aws" }

  name        = each.key
  environment = local.general.environment
  ssh_user    = local.resolved_aws_ssh_user
  ssh_port    = local.general.ssh_port

  instance_type = lookup(
    local.cloud_machine_types,
    lookup(each.value, "machine_type", local.general.default_machine_type),
    lookup(each.value, "machine_type", local.resolved_default_machine_type)
  )

  ami_id = lookup(
    local.cloud_os_images,
    lookup(each.value, "os_image", local.general.default_os),
    lookup(each.value, "os_image", local.resolved_default_os)
  )

  disk_type = lookup(
    local.cloud_disk_types,
    lookup(each.value, "disk_type", local.general.default_disk_type),
    lookup(each.value, "disk_type", local.resolved_default_disk_type)
  )

  disk_size_gb = lookup(each.value, "disk_size_gb", local.general.default_disk_size_gb)

  subnet_id = module.network_aws[each.value.network].subnet_ids[each.value.subnet]
  security_group_ids = [
    for fw_name, fw in module.firewall_aws :
    fw.security_group_id
    if length(setintersection(
      toset(lookup(each.value, "tags", [])),
      toset(local.firewall_rules[fw_name].target_tags)
    )) > 0
  ]
  key_name         = aws_key_pair.this[0].key_name
  assign_public_ip = lookup(each.value, "assign_public_ip", false)

  tags = lookup(each.value, "labels", {})
}

# ============================================================================
# AZURE RESOURCES (active when var.cloud == "azure")
# ============================================================================

module "network_azure" {
  source   = "../../modules/azure/network"
  for_each = { for name, network in local.networks : name => network if var.cloud == "azure" }

  name                = each.key
  resource_group_name = local.azure_resource_group_name
  location            = local.azure_location

  subnets = {
    for subnet_name, subnet in local.subnets :
    subnet_name => {
      cidr = subnet.cidr
    }
    if subnet.network == each.key
  }

  tags = {
    ManagedBy   = "terraform"
    Environment = local.general.environment
  }
}

module "firewall_azure" {
  source   = "../../modules/azure/firewall"
  for_each = { for name, rule in local.firewall_rules : name => rule if var.cloud == "azure" }

  name                = each.key
  resource_group_name = local.azure_resource_group_name
  location            = local.azure_location

  ingress_rules = [
    for idx, port_range in lookup(each.value, "ports", ["*"]) : {
      name        = "${each.key}-${idx}"
      priority    = 100 + (index(keys(local.firewall_rules), each.key) * 10) + idx
      protocol    = lookup(each.value, "protocol", "Tcp") == "tcp" ? "Tcp" : (lookup(each.value, "protocol", "tcp") == "udp" ? "Udp" : (lookup(each.value, "protocol", "tcp") == "icmp" ? "Icmp" : "*"))
      port        = port_range == "0-65535" ? "*" : port_range
      source      = length(lookup(each.value, "source_ranges", [])) > 0 ? each.value.source_ranges[0] : "*"
      description = each.value.description
    }
  ]

  tags = {
    ManagedBy   = "terraform"
    Environment = local.general.environment
  }

  depends_on = [module.network_azure]
}

module "vm_azure" {
  source   = "../../modules/azure/vm"
  for_each = { for name, vm in local.vms : name => vm if var.cloud == "azure" }

  name                = each.key
  resource_group_name = local.azure_resource_group_name
  location            = local.azure_location

  instance_type = lookup(
    local.cloud_machine_types,
    lookup(each.value, "machine_type", local.general.default_machine_type),
    lookup(each.value, "machine_type", local.resolved_default_machine_type)
  )

  os_image = lookup(
    local.cloud_os_images,
    lookup(each.value, "os_image", local.general.default_os),
    lookup(each.value, "os_image", local.resolved_default_os)
  )

  disk_type = lookup(
    local.cloud_disk_types,
    lookup(each.value, "disk_type", local.general.default_disk_type),
    lookup(each.value, "disk_type", local.resolved_default_disk_type)
  )

  disk_size_gb = max(lookup(each.value, "disk_size_gb", local.general.default_disk_size_gb), 30)

  subnet_id = module.network_azure[each.value.network].subnet_ids[each.value.subnet]

  nsg_id = length([for n in keys(local.firewall_rules) : n]) > 0 ? module.firewall_azure[keys(local.firewall_rules)[0]].nsg_id : null

  ssh_user         = local.resolved_azure_ssh_user
  ssh_public_key   = var.ssh_public_key
  ssh_port         = local.general.ssh_port
  assign_public_ip = lookup(each.value, "assign_public_ip", false)

  tags = lookup(each.value, "labels", {})

  depends_on = [module.network_azure, module.firewall_azure]
}
