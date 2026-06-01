output "bastion_public_ip" {
  value = google_compute_instance.bastion.network_interface[0].access_config[0].nat_ip
}

output "bastion_private_ip" {
  value = google_compute_instance.bastion.network_interface[0].network_ip
}

output "cluster_private_ips" {
  value = {
    for name, instance in google_compute_instance.nodes : name => instance.network_interface[0].network_ip
  }
}

output "traefik_public_ip" {
  value = google_compute_global_address.traefik_public_ip.address
}

output "traefik_public_http_url" {
  value = "http://${google_compute_global_address.traefik_public_ip.address}"
}

output "traefik_public_https_url" {
  value = "https://${google_compute_global_address.traefik_public_ip.address}"
}

output "traefik_nodeports" {
  value = {
    http  = var.traefik_http_nodeport
    https = var.traefik_https_nodeport
  }
}

output "ansible_inventory_ini" {
  value = local.ansible_inventory_ini
}

output "ansible_inventory_path" {
  value = local_file.ansible_inventory.filename
}

output "kubectl_tunnel_command" {
  value = "ssh -J ${var.ssh_user}@${google_compute_instance.bastion.network_interface[0].access_config[0].nat_ip} -i ~/.ssh/id_rsa -N -L 6443:127.0.0.1:6443 ${var.ssh_user}@${google_compute_instance.nodes["cp-1"].network_interface[0].network_ip}"
}

output "headlamp_tunnel_command" {
  value = "ssh -J ${var.ssh_user}@${google_compute_instance.bastion.network_interface[0].access_config[0].nat_ip} -i ~/.ssh/id_rsa -N -L 30082:${google_compute_instance.nodes["cp-1"].network_interface[0].network_ip}:30082 ${var.ssh_user}@${google_compute_instance.nodes["cp-1"].network_interface[0].network_ip}"
}
