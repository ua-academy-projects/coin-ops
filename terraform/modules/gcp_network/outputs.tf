output "vpc_name" {
  description = "VPC network name"
  value = try(google_compute_network.vpc[0].name, null)
}

output "subnet_id" {
  description = "Subnet ID"
  value = try(google_compute_subnetwork.subnet[0].id, null)
}

output "vpc_id" {
  description = "VPC network self link — used for CloudSQL private networking"
  value = try(google_compute_network.vpc[0].self_link, null)
}