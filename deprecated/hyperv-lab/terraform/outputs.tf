output "node_ips" {
  description = "Static IPs assigned via cloud-init"
  value = {
    history = "172.31.1.10"
    proxy   = "172.31.1.11"
    ui      = "172.31.1.12"
  }
}

output "ansible_inventory" {
  description = "Paste this into ansible/inventory after terraform apply"
  value = <<-INV
    [history]
    softserve-node-01 ansible_host=172.31.1.10

    [proxy]
    softserve-node-02 ansible_host=172.31.1.11

    [ui]
    softserve-node-03 ansible_host=172.31.1.12

    [all:vars]
    ansible_user=vagrant
  INV
}

output "next_steps" {
  description = "What to do after terraform apply"
  value = <<-STEPS
    1. Wait ~2 min for cloud-init to finish on all VMs
    2. Test SSH: ssh vagrant@172.31.1.10
    3. Run Ansible: ansible-playbook -i ansible/inventory ansible/provision.yml
    4. Deploy services: ansible-playbook -i ansible/inventory ansible/deploy.yml
  STEPS
}
