output "node_ips" {
  description = "Static IPs assigned via cloud-init"
  value       = { for name, node in local.nodes : node.role => node.ip }
}

output "ansible_inventory" {
  description = "Generated Ansible inventory content"
  value       = local.ansible_inventory
}

output "ansible_inventory_path" {
  description = "Generated Ansible inventory file path"
  value       = local_file.ansible_inventory.filename
}

output "next_steps" {
  description = "What to do after terraform apply"
  value       = <<-STEPS
    1. Wait ~2 min for cloud-init to finish on all VMs
    2. Test SSH: ssh vagrant@172.31.1.10
    3. Run Ansible: ansible-playbook -i ansible/inventory.generated ansible/provision.yml
    4. Deploy services: ansible-playbook -i ansible/inventory.generated ansible/deploy.yml
  STEPS
}
