locals {
  bastion_outputs = {
    for name, instance in aws_instance.bastion : name => {
      name       = var.instances[name].name
      role       = "bastion"
      private_ip = instance.private_ip
      public_ip  = instance.public_ip
    }
  }

  app_outputs = {
    for name, instance in aws_instance.app : name => {
      name       = var.instances[name].name
      role       = "app"
      private_ip = instance.private_ip
      public_ip  = instance.public_ip
    }
  }

  db_outputs = {
    for name, instance in aws_instance.db : name => {
      name       = var.instances[name].name
      role       = "db"
      private_ip = instance.private_ip
      public_ip  = instance.public_ip
    }
  }
}

output "instances" {
  value = merge(local.bastion_outputs, local.app_outputs, local.db_outputs)
}

output "app_instances" {
  value = {
    for name, instance in aws_instance.app : name => merge(local.app_outputs[name], {
      id = instance.id
    })
  }
}

output "bastion_instances" {
  value = local.bastion_outputs
}

output "db_instances" {
  value = local.db_outputs
}
