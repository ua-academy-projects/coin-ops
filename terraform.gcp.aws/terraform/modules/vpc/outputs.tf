output "network_name" {
  value = try(google_compute_network.vpc[0].name, null)
}

output "subnet_id" {
  value = try(google_compute_subnetwork.subnet[0].id, null)
}

output "vpc_id" {
  value = try(aws_vpc.main[0].id, null)
}

output "public_subnet_id" {
  value = try(aws_subnet.subnets["public-a"].id, null)
}

output "private_subnet_id" {
  value = try(aws_subnet.subnets["private-a"].id, null)
}

output "public_subnet_ids" {
  value = [
    for name, subnet in aws_subnet.subnets : subnet.id
    if var.config.network.aws_subnets[name].public
  ]
}
output "private_subnet_ids" {
  value = [
    for name, subnet in aws_subnet.subnets : subnet.id
    if !var.config.network.aws_subnets[name].public
  ]
}
