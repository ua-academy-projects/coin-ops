output "endpoint" {
  value = aws_lb.ui.dns_name
}

output "endpoint_type" {
  value = "CNAME"
}

output "instances" {
  value = {
    ui = {
      name       = local.name
      role       = "ui"
      private_ip = aws_instance.ui.private_ip
      public_ip  = aws_instance.ui.public_ip
    }
  }
}

output "ssh_config" {
  value = local.ssh_config
}

output "ansible_inventory" {
  value = local.ansible_inventory
}
