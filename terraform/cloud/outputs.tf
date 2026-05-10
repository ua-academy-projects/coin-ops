# outputs.tf


output "instance_names" {
  value = var.cloud == "gcp" ? try(module.gcp_instances[0].instance_names, {}) : try(module.aws_instances[0].instance_names, {})
}


output "private_ips" {
  value = var.cloud == "gcp" ? try(module.gcp_instances[0].private_ips, {}) : try(module.aws_instances[0].private_ips, {})
}


output "public_ips" {
  value = var.cloud == "gcp" ? try(module.gcp_instances[0].public_ips, {}) : try(module.aws_instances[0].public_ips, {})
}
