# outputs.tf

output "network_name" {
  value = aws_vpc.this.tags.Name
}


output "network_id" {
  value = aws_vpc.this.id
}


output "subnetwork_names" {
  value = { for key, subnet in aws_subnet.this : key => subnet.tags.Name }
}


output "subnetwork_ids" {
  value = { for key, subnet in aws_subnet.this : key => subnet.id }
}
