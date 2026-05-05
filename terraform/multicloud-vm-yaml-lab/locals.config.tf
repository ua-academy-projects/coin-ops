locals {
  raw = yamldecode(file("${path.module}/config/lab.yaml"))

  base_config = {
    cloud       = "aws"
    location    = "eu_central"
    name_prefix = "coinops-lab"
    ssh = {
      user             = "vova"
      public_key_path  = "~/.ssh/coinops_gcp_jump.pub"
      private_key_path = "~/.ssh/coinops_gcp_jump"
    }
    domain = {
      enabled            = false
      name               = ""
      cloudflare_zone_id = ""
      create_records     = false
    }
    firewall = {
      ssh_source_ranges       = []
      web_source_ranges       = ["0.0.0.0/0"]
      allow_icmp_from_bastion = false
    }
    defaults = {
      size         = "micro"
      image        = "ubuntu_2204"
      disk_size_gb = 10
      network      = "lab"
    }
    app = {
      port        = 80
      health_path = "/health"
      nodes = {
        bastion = "bastion"
        app     = ["app-1", "app-2"]
        db      = "db"
      }
    }
  }

  config = merge(local.base_config, local.raw, {
    ssh      = merge(local.base_config.ssh, try(local.raw.ssh, {}))
    domain   = merge(local.base_config.domain, try(local.raw.domain, {}))
    firewall = merge(local.base_config.firewall, try(local.raw.firewall, {}))
    defaults = merge(local.base_config.defaults, try(local.raw.defaults, {}))
    app = merge(local.base_config.app, try(local.raw.app, {}), {
      nodes = merge(local.base_config.app.nodes, try(local.raw.app.nodes, {}))
    })
  })

  cloud  = lower(local.config.cloud)
  is_aws = local.cloud == "aws"
  is_gcp = local.cloud == "gcp"

  aws_location = local.config.catalog.locations[local.config.location].aws
  gcp_location = local.config.catalog.locations[local.config.location].gcp
  aws_region   = local.aws_location.region
  gcp_region   = local.gcp_location.region
  gcp_zone     = local.gcp_location.zone
}
