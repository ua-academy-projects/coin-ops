# locals.tf

locals {
  mappings = jsondecode(file("${path.module}/mappings.json"))


  instances = {
    for name, cfg in var.workloads : name => {
      instance_type        = local.mappings.instance_type[cfg.instance_type]
      ami                  = local.mappings.image_family[cfg.image_family]
      availability_zone    = local.mappings.placement[cfg.placement].instance_zone
      subnet_id            = var.subnetworks[cfg.subnet]
      tags                 = distinct(concat(cfg.tags, [name]))
      disk_size_gb         = cfg.disk_size_gb
      public_ip            = cfg.public_ip
      can_ip_forward       = cfg.can_ip_forward
      iam_instance_profile = try(cfg.identity, null) != null ? "coinops-${cfg.identity}" : null
    }
  }

  workload_identities = {
    for identity in distinct([
      for _, cfg in var.workloads : cfg.identity
      if try(cfg.identity, null) != null
      ]) : identity => {
      name = "coinops-${identity}"
    }
  }

  secret_access_bindings = {
    for binding in flatten([
      for identity, identity_cfg in local.workload_identities : [
        for workload_name, cfg in var.workloads : [
          for secret in try(cfg.secrets, []) : {
            key         = "${identity}-${secret}"
            identity    = identity
            secret_key  = secret
            secret_name = var.secrets[secret].secret_id
          }
          if try(cfg.identity, null) == identity
        ]
      ]
    ]) : binding.key => binding
  }

}
