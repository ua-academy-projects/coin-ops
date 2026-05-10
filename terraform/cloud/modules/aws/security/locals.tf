# locals.tf

locals {
  mappings = jsondecode(file("${path.module}/mappings.json"))

  workload_security_groups = {
    for name in var.workload_names : name => {
      description = "Security group for ${name}"
    }
  }

  target_rule_pairs = flatten([
    for rule_name, rule in var.rules : [
      for target in rule.target_workloads : {
        key              = "${rule_name}:${target}"
        rule_name        = rule_name
        target_workload  = target
        description      = rule.description
        type             = local.mappings.direction[upper(rule.direction)]
        protocol         = rule.protocol
        ports            = rule.ports
        cidr_blocks      = rule.cidr_blocks
        source_workloads = rule.source_workloads
      }
    ]
  ])

  rules_by_target = {
    for pair in local.target_rule_pairs : pair.key => pair
  }

  cidr_rules = {
    for item in flatten([
      for key, rule in local.rules_by_target : [
        for cidr in rule.cidr_blocks : [
          for port in rule.ports : {
            key             = "${key}:${cidr}:${port}"
            target_workload = rule.target_workload
            description     = rule.description
            type            = rule.type
            protocol        = rule.protocol
            port            = port
            cidr_block      = cidr
          }
        ]
      ]
    ]) : item.key => item
  }

  source_workload_rules = {
    for item in flatten([
      for key, rule in local.rules_by_target : [
        for source in rule.source_workloads : {
          rule_key        = key
          source_workload = source
          target_workload = rule.target_workload
          description     = rule.description
          type            = rule.type
          protocol        = rule.protocol
          ports           = rule.ports
        }
      ]
    ]) : item.rule_key => item...
  }

  source_workload_port_rules = {
    for item in flatten([
      for key, rules in local.source_workload_rules : flatten([
        for rule in rules : [
          for port in rule.ports : {
            key             = "${key}:${rule.source_workload}:${port}"
            target_workload = rule.target_workload
            description     = rule.description
            type            = rule.type
            protocol        = rule.protocol
            port            = port
            source_workload = rule.source_workload
          }
        ]
      ])
    ]) : item.key => item
  }
}
