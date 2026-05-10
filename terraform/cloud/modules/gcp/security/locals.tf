# locals.tf

locals {
  rules = {
    for key, rule in var.rules : key => {
      name          = "coinops-${replace(key, "_", "-")}"
      description   = rule.description
      direction     = upper(rule.direction)
      priority      = rule.priority
      source_ranges = rule.cidr_blocks
      source_tags   = distinct(flatten([for workload in rule.source_workloads : var.workload_selectors[workload]]))
      target_tags   = distinct(flatten([for workload in rule.target_workloads : var.workload_selectors[workload]]))
      allows = [
        {
          protocol = rule.protocol
          ports    = rule.ports
        }
      ]
    }
  }
}
