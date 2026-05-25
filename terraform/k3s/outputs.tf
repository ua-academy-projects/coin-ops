# =============================================================================
# k3s/outputs.tf
# =============================================================================
# Surface all connection details, IP addresses, and operational runbooks
# as Terraform outputs for use by CI/CD pipelines and operators.
# =============================================================================

# ─── Load Balancer IPs ───────────────────────────────────────────────────────

output "k3s_api_lb_ip" {
  description = "Internal IP of the k3s API Server Load Balancer (port 6443). Only reachable from within the VPC or via the Bastion SSH tunnel."
  value       = google_compute_address.k3s_api_vip.address
}

output "nginx_ingress_external_ip" {
  description = "External IP of the NGINX Ingress Load Balancer. Point your DNS A records here."
  value       = google_compute_forwarding_rule.nginx_http.ip_address
}

# ─── Bastion Host ─────────────────────────────────────────────────────────────

output "bastion_zone" {
  description = "Zone where the Bastion Host is running."
  value       = google_compute_instance.bastion.zone
}

output "bastion_name" {
  description = "Name of the Bastion Host instance."
  value       = google_compute_instance.bastion.name
}

output "bastion_external_ip" {
  description = "External IP of the Bastion Host (used by IAP — not directly reachable)."
  value       = google_compute_instance.bastion.network_interface[0].access_config[0].nat_ip
}

# ─── k3s Node IPs ────────────────────────────────────────────────────────────

output "k3s_node_internal_ips" {
  description = "Internal (private subnet) IP addresses of each k3s control-plane node."
  value = {
    for i, node in google_compute_instance.k3s_nodes :
    "k3s-node-${i}" => node.network_interface[0].network_ip
  }
}

# ─── SSH Key (sensitive) ──────────────────────────────────────────────────────

output "ssh_private_key_secret" {
  description = "GCP Secret Manager resource ID for the k3s SSH private key. Use this to pull the key: gcloud secrets versions access latest --secret=k3s-ssh-private-key"
  value       = google_secret_manager_secret.k3s_ssh_private_key.name
}

# ─── Connection Runbooks ──────────────────────────────────────────────────────

output "connect_bastion_command" {
  description = "IAP-authenticated SSH command to connect to the Bastion Host (no VPN or exposed TCP:22 required)."
  value       = <<-EOT
    # ── Connect to Bastion via IAP ────────────────────────────────────────────
    gcloud compute ssh ${google_compute_instance.bastion.name} \
      --project=${local.project_id} \
      --zone=${google_compute_instance.bastion.zone} \
      --tunnel-through-iap
  EOT
}

output "fetch_kubeconfig_command" {
  description = "Commands to extract the kubeconfig from node-0 via the Bastion and configure kubectl locally."
  value       = <<-EOT
    # ── Step 1: Save the SSH private key ─────────────────────────────────────
    # (Run once — key is fetched from GCP Secret Manager)
    gcloud secrets versions access latest --secret="k3s-ssh-private-key" --project="${local.project_id}" > ~/.ssh/k3s_id_rsa
    chmod 600 ~/.ssh/k3s_id_rsa

    # ── Step 2: Open an SSH tunnel through the Bastion ────────────────────────
    # This forwards your local port 16443 → Internal LB → k3s API (6443)
    # Run this in a background terminal or use -f -N flags
    gcloud compute ssh ${google_compute_instance.bastion.name} \
      --project=${local.project_id} \
      --zone=${google_compute_instance.bastion.zone} \
      --tunnel-through-iap \
      -- \
      -i ~/.ssh/k3s_id_rsa \
      -L 16443:${google_compute_address.k3s_api_vip.address}:6443 \
      -N -f

    # ── Step 3: Copy kubeconfig from node-0 via Bastion jump host ────────────
    ssh -i ~/.ssh/k3s_id_rsa \
      -o StrictHostKeyChecking=no \
      -o ProxyCommand="gcloud compute start-iap-tunnel ${google_compute_instance.bastion.name} 22 --listen-on-stdin --project=${local.project_id} --zone=${google_compute_instance.bastion.zone}" \
      -J ubuntu@${google_compute_instance.bastion.network_interface[0].access_config[0].nat_ip} \
      ubuntu@${google_compute_instance.k3s_nodes[0].network_interface[0].network_ip} \
      "sudo cat /etc/rancher/k3s/k3s.yaml" \
    | sed 's|https://127.0.0.1:6443|https://127.0.0.1:16443|g' \
    > ~/.kube/k3s-config.yaml

    # ── Step 4: Merge into your kubeconfig ───────────────────────────────────
    KUBECONFIG=~/.kube/config:~/.kube/k3s-config.yaml \
      kubectl config view --flatten > ~/.kube/config-merged
    mv ~/.kube/config-merged ~/.kube/config

    # ── Step 5: Switch context ────────────────────────────────────────────────
    kubectl config use-context default
    kubectl get nodes
  EOT
}

output "kubectl_tunnel_command" {
  description = "Persistent SSH tunnel command for kubectl access. Run this in a background terminal before using kubectl."
  value       = <<-EOT
    # ── Persistent kubectl tunnel (run in background) ─────────────────────────
    # While this tunnel is open, kubectl talks to the k3s cluster via localhost.
    gcloud compute ssh ${google_compute_instance.bastion.name} \
      --project=${local.project_id} \
      --zone=${google_compute_instance.bastion.zone} \
      --tunnel-through-iap \
      -- \
      -i ~/.ssh/k3s_id_rsa \
      -L 16443:${google_compute_address.k3s_api_vip.address}:6443 \
      -N

    # kubectl is now operational:
    # kubectl get nodes
    # kubectl get pods -A
  EOT
}

output "headlamp_access_command" {
  description = "Commands to access the Headlamp dashboard locally via port-forward through the kubectl tunnel."
  value       = <<-EOT
    # ── Access Headlamp Dashboard ─────────────────────────────────────────────
    # (Requires kubectl tunnel to be active — see kubectl_tunnel_command output)

    # Port-forward Headlamp to local port 4466
    kubectl -n headlamp port-forward svc/headlamp 4466:80 &

    # Get a login token
    kubectl -n headlamp create token headlamp

    # Open the dashboard
    open http://localhost:4466
  EOT
}

output "ssh_multi_hop_example" {
  description = "Example of SSH multi-hop routing through the Bastion to reach a specific k3s node."
  value       = <<-EOT
    # ══════════════════════════════════════════════════════════════════════════
    # Multi-hop SSH routing: Local → IAP Tunnel → Bastion → k3s Node
    # ══════════════════════════════════════════════════════════════════════════
    #
    # The Bastion is the ONLY entry point to the private subnet.
    # The -J flag (ProxyJump) chains SSH connections automatically.
    #
    # ── Direct SSH to k3s-node-0 via Bastion ─────────────────────────────────
    ssh -i ~/.ssh/k3s_id_rsa \
      -o StrictHostKeyChecking=no \
      -J ubuntu@${google_compute_instance.bastion.network_interface[0].access_config[0].nat_ip} \
      ubuntu@${google_compute_instance.k3s_nodes[0].network_interface[0].network_ip}

    # ── Check k3s cluster status on node-0 ───────────────────────────────────
    #  (once connected to the node)
    sudo k3s kubectl get nodes -o wide
    sudo systemctl status k3s

    # ── Check embedded etcd cluster health ───────────────────────────────────
    sudo k3s etcd-snapshot ls
    ETCDCTL_ENDPOINTS="https://127.0.0.1:2379" \
    ETCDCTL_CACERT="/var/lib/rancher/k3s/server/tls/etcd/server-ca.crt" \
    ETCDCTL_CERT="/var/lib/rancher/k3s/server/tls/etcd/client.crt" \
    ETCDCTL_KEY="/var/lib/rancher/k3s/server/tls/etcd/client.key" \
    ETCDCTL_API=3 \
    etcdctl member list
  EOT
}
