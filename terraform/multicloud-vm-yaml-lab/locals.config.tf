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
    secrets = {
      prefix = "coinops-lab"
      items = {
        db_password       = "db-password"
        rabbitmq_password = "rabbitmq-password"
        ghcr_token        = "ghcr-token"
        cloudflare_token  = "cloudflare-token"
      }
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
    runtime = {
      mode = "external"
      database = {
        mode                = "vm"
        engine              = "postgres"
        version             = "16"
        name                = "cognitor"
        user                = "cognitor"
        size                = "small"
        storage_gb          = 20
        publicly_accessible = false
      }
      queue = {
        mode                       = "container"
        name                       = "market-events"
        dead_letter                = true
        visibility_timeout_seconds = 30
        max_receive_count          = 3
      }
      sessions = {
        backend   = "redis"
        ttl_hours = 24
      }
      cache = {
        mode               = "container"
        engine             = "redis"
        size               = "micro"
        port               = 6379
        auth               = false
        transit_encryption = false
      }
    }
  }

  config = merge(local.base_config, local.raw, {
    ssh      = merge(local.base_config.ssh, try(local.raw.ssh, {}))
    domain   = merge(local.base_config.domain, try(local.raw.domain, {}))
    firewall = merge(local.base_config.firewall, try(local.raw.firewall, {}))
    defaults = merge(local.base_config.defaults, try(local.raw.defaults, {}))
    secrets = merge(local.base_config.secrets, try(local.raw.secrets, {}), {
      items = merge(local.base_config.secrets.items, try(local.raw.secrets.items, {}))
    })
    app = merge(local.base_config.app, try(local.raw.app, {}), {
      nodes = merge(local.base_config.app.nodes, try(local.raw.app.nodes, {}))
    })
    runtime = merge(local.base_config.runtime, try(local.raw.runtime, {}), {
      database = merge(local.base_config.runtime.database, try(local.raw.runtime.database, {}))
      queue    = merge(local.base_config.runtime.queue, try(local.raw.runtime.queue, {}))
      sessions = merge(local.base_config.runtime.sessions, try(local.raw.runtime.sessions, {}))
      cache    = merge(local.base_config.runtime.cache, try(local.raw.runtime.cache, {}))
    })
  })

  cloud  = lower(local.config.cloud)
  is_aws = local.cloud == "aws"
  is_gcp = local.cloud == "gcp"

  aws_location = local.config.catalog.locations[local.config.location].aws
  gcp_location = local.config.catalog.locations[local.config.location].gcp
  gcp_zones    = try(local.gcp_location.zones, [local.gcp_location.zone])
  aws_region   = local.aws_location.region
  gcp_region   = local.gcp_location.region
  gcp_zone     = local.gcp_zones[0]

  network_key = local.config.defaults.network
  network_raw = local.config.networks[local.network_key]

  public_subnets = {
    for idx, cidr in local.network_raw.public_subnet_cidrs : tostring(idx) => {
      name     = "${local.config.name_prefix}-public-${idx}"
      cidr     = cidr
      aws_az   = local.aws_location.availability_zones[idx % length(local.aws_location.availability_zones)]
      gcp_zone = local.gcp_zones[idx % length(local.gcp_zones)]
    }
  }

  private_subnets = {
    for idx, cidr in local.network_raw.private_subnet_cidrs : tostring(idx) => {
      name     = "${local.config.name_prefix}-private-${idx}"
      cidr     = cidr
      aws_az   = local.aws_location.availability_zones[idx % length(local.aws_location.availability_zones)]
      gcp_zone = local.gcp_zones[idx % length(local.gcp_zones)]
    }
  }

  app_names    = local.config.app.nodes.app
  db_name      = local.config.app.nodes.db
  bastion_name = local.config.app.nodes.bastion

  database_size_key = try(local.config.runtime.database.size, "small")
  database_size = try(local.config.catalog.database_sizes[local.database_size_key], {
    aws = "db.t4g.micro"
    gcp = "db-f1-micro"
  })
  cache_size_key = try(local.config.runtime.cache.size, "micro")
  cache_size = try(local.config.catalog.cache_sizes[local.cache_size_key], {
    aws = {
      node_type      = "cache.t4g.micro"
      engine_version = "7.2"
      replicas       = 0
    }
    gcp = {
      node_type      = "SHARED_CORE_NANO"
      engine_version = "VALKEY_8_0"
      shard_count    = 1
      replica_count  = 0
    }
  })
  runtime_mode     = replace(lower(try(local.config.runtime.mode, "external")), "-", "_")
  cloud_native     = local.runtime_mode == "cloud_native"
  database_managed = local.cloud_native && try(local.config.runtime.database.mode, "") == "managed_postgres"
  queue_managed    = local.cloud_native && try(local.config.runtime.queue.mode, "") == "managed"
  cache_managed    = local.cloud_native && try(local.config.runtime.cache.mode, "") == "managed_valkey"

  runtime = {
    mode = local.runtime_mode
    database = merge(local.config.runtime.database, {
      managed              = local.database_managed
      port                 = 5432
      aws_instance_class   = try(local.database_size.aws, "db.t4g.micro")
      gcp_tier             = try(local.database_size.gcp, "db-f1-micro")
      gcp_database_version = "POSTGRES_${replace(tostring(local.config.runtime.database.version), ".", "_")}"
    })
    queue = merge(local.config.runtime.queue, {
      managed = local.queue_managed
    })
    sessions = local.config.runtime.sessions
    cache = merge(local.config.runtime.cache, {
      managed            = local.cache_managed
      backend            = local.cache_managed ? "valkey" : try(local.config.runtime.cache.engine, "redis")
      port               = try(local.config.runtime.cache.port, 6379)
      aws_node_type      = try(local.cache_size.aws.node_type, "cache.t4g.micro")
      aws_engine_version = try(local.cache_size.aws.engine_version, "7.2")
      aws_replicas       = try(local.cache_size.aws.replicas, 0)
      gcp_node_type      = try(local.cache_size.gcp.node_type, "SHARED_CORE_NANO")
      gcp_engine_version = try(local.cache_size.gcp.engine_version, "VALKEY_8_0")
      gcp_shard_count    = try(local.cache_size.gcp.shard_count, 1)
      gcp_replica_count  = try(local.cache_size.gcp.replica_count, 0)
    })
  }

  image_catalog = {
    for image_key, image_config in local.config.catalog.images : image_key => {
      aws = image_config.aws
      gcp = image_config.gcp
    }
  }

  instances = {
    for instance_key, instance in local.config.instances : instance_key => {
      key               = instance_key
      name              = "${local.config.name_prefix}-${instance_key}"
      role              = instance.role
      private_ip        = instance.private_ip
      public_ip         = local.config.roles[instance.role].public_ip
      tags              = local.config.roles[instance.role].tags
      size_key          = lookup(instance, "size", local.config.defaults.size)
      image_key         = lookup(instance, "image", local.config.defaults.image)
      disk_size_gb      = lookup(instance, "disk_size_gb", local.config.defaults.disk_size_gb)
      aws_instance_type = local.config.catalog.sizes[lookup(instance, "size", local.config.defaults.size)].aws
      gcp_machine_type  = local.config.catalog.sizes[lookup(instance, "size", local.config.defaults.size)].gcp
      gcp_image         = local.config.catalog.images[lookup(instance, "image", local.config.defaults.image)].gcp
    }
  }

  stack = {
    cloud       = local.cloud
    name_prefix = local.config.name_prefix
    ssh         = local.config.ssh
    domain      = local.config.domain
    firewall    = local.config.firewall
    defaults    = local.config.defaults
    app         = local.config.app
    runtime     = local.runtime
    secrets     = local.config.secrets

    network = {
      key             = local.network_key
      name            = local.network_raw.name
      cidr            = local.network_raw.cidr
      subnet_name     = local.network_raw.subnet_name
      gcp_subnet_cidr = try(local.network_raw.gcp_subnet_cidr, null)
      public_subnets  = local.public_subnets
      private_subnets = local.private_subnets
    }

    aws = {
      region                    = local.aws_region
      availability_zones        = local.aws_location.availability_zones
      profile                   = try(local.config.clouds.aws.profile, null)
      app_instance_profile_name = try(local.config.clouds.aws.app_instance_profile_name, "${local.config.name_prefix}-app-runtime-profile")
    }

    gcp = {
      project_id = try(local.config.clouds.gcp.project_id, null)
      region     = local.gcp_region
      zone       = local.gcp_zone
      zones      = local.gcp_zones
    }

    image_catalog  = local.image_catalog
    instances      = local.instances
    bastion_name   = local.bastion_name
    app_names      = local.app_names
    db_name        = local.db_name
    ssh_public_key = trimspace(file(pathexpand(local.config.ssh.public_key_path)))
  }
}
