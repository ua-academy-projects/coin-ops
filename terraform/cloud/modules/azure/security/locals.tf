locals {
  mappings = jsondecode(file("${path.module}/mappings.json"))

  subnet_exposure = {
    for key, subnet in var.subnets : key => subnet.exposure
  }

  workload_names = keys(var.workloads)

  workload_subnets = {
    for key, workload in var.workloads : key => workload.subnet
  }

  workload_application_security_groups = {
    for name in local.workload_names : name => {
      name = "asg-${name}"
    }
  }

  subnet_network_security_groups = {
    for subnet_name, exposure in local.subnet_exposure : subnet_name => {
      name = "nsg-${subnet_name}"
    }
  }

  cidr_rule_pairs = flatten([
    for rule_name, rule in var.rules : [
      for target in rule.target_workloads : [
        for port in length(rule.ports) > 0 ? rule.ports : ["*"] : [
          for cidr in rule.cidr_blocks : {
            key                = "${rule_name}:${target}:${cidr}:${port}"
            subnet_key         = local.workload_subnets[target]
            description        = rule.description
            direction          = local.mappings.direction[upper(rule.direction)]
            access             = "Allow"
            base_priority      = rule.priority
            protocol           = local.mappings.protocol[lower(rule.protocol)]
            source_port        = "*"
            destination_port   = port
            source_prefix      = cidr
            destination_prefix = "*"
            source_workload    = null
            target_workload    = target
            kind               = "cidr"
          }
        ]
      ]
    ]
  ])

  source_workload_rule_pairs = flatten([
    for rule_name, rule in var.rules : [
      for target in rule.target_workloads : [
        for source in rule.source_workloads : [
          for port in length(rule.ports) > 0 ? rule.ports : ["*"] : [
            {
              key                = "${rule_name}:${source}:${target}:${port}"
              subnet_key         = local.workload_subnets[target]
              description        = rule.description
              direction          = local.mappings.direction[upper(rule.direction)]
              access             = "Allow"
              base_priority      = rule.priority
              protocol           = local.mappings.protocol[lower(rule.protocol)]
              source_port        = "*"
              destination_port   = port
              source_prefix      = null
              destination_prefix = null
              source_workload    = source
              target_workload    = target
              kind               = "workload"
            }
          ]
        ]
      ]
    ]
  ])

  all_rule_pairs = concat(local.cidr_rule_pairs, local.source_workload_rule_pairs)

  ordered_rule_keys = sort([
    for rule in local.all_rule_pairs : "${rule.subnet_key}|${rule.base_priority}|${rule.key}"
  ])

  priority_by_key = {
    for idx, ordered_key in local.ordered_rule_keys :
    split("|", ordered_key)[2] => 100 + idx
  }

  cidr_rules = {
    for rule in local.cidr_rule_pairs : rule.key => merge(rule, {
      priority = local.priority_by_key[rule.key]
    })
  }

  workload_rules = {
    for rule in local.source_workload_rule_pairs : rule.key => merge(rule, {
      priority = local.priority_by_key[rule.key]
    })
  }
}
