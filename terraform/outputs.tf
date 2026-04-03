output "node_history_ip" {
  description = "Public IP of history node (node-01) — use in ansible/inventory [history]"
  value       = aws_instance.node_history.public_ip
}

output "node_proxy_ip" {
  description = "Public IP of proxy node (node-02) — use in ansible/inventory [proxy]"
  value       = aws_instance.node_proxy.public_ip
}

output "node_ui_ip" {
  description = "Public IP of UI node (node-03) — use in ansible/inventory [ui] and browser"
  value       = aws_instance.node_ui.public_ip
}

output "ansible_inventory_snippet" {
  description = "Paste this into ansible/inventory after provisioning"
  value = <<-EOT
    [history]
    softserve-node-01 ansible_host=${aws_instance.node_history.public_ip}

    [proxy]
    softserve-node-02 ansible_host=${aws_instance.node_proxy.public_ip}

    [ui]
    softserve-node-03 ansible_host=${aws_instance.node_ui.public_ip}
  EOT
}
