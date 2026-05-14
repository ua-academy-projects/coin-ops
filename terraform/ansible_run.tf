resource "null_resource" "run_ansible" {
  count = var.run_ansible ? 1 : 0

  triggers = {
    inventory = local_file.ansible_inventory.content
    nodes     = jsonencode(local.nodes)
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      repo_root="$(cd "${path.module}/.." && pwd)"
      inventory="${local_file.ansible_inventory.filename}"
      env_file="${path.module}/${var.ansible_env_file}"

      if [ -f "$env_file" ]; then
        set -a
        . "$env_file"
        set +a
      fi

      deadline=$((SECONDS + ${var.ansible_ssh_wait_timeout_seconds}))
      for host in ${join(" ", [for node in values(local.nodes) : node.ip])}; do
        until ssh \
          -o BatchMode=yes \
          -o StrictHostKeyChecking=no \
          -o UserKnownHostsFile=/dev/null \
          -o ConnectTimeout=5 \
          "${var.ansible_user}@$host" true; do
          if [ "$SECONDS" -ge "$deadline" ]; then
            echo "Timed out waiting for SSH on $host" >&2
            exit 1
          fi
          sleep 5
        done
      done

      ansible-galaxy collection install -r "$repo_root/ansible/requirements.yml"
      ansible-playbook -i "$inventory" "$repo_root/ansible/provision.yml"
      ansible-playbook -i "$inventory" "$repo_root/ansible/deploy.yml"
    EOT
  }

  depends_on = [
    hyperv_machine_instance.node,
    local_file.ansible_inventory,
  ]
}
