#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/../.." && pwd)"
ANSIBLE_DIR="$REPO_ROOT/ansible"
RUN_ANSIBLE="${RUN_ANSIBLE:-false}"

read_cloud() {
  awk -F: '/^cloud:[[:space:]]*/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$ROOT_DIR/config/lab.yaml"
}

CLOUD="${CLOUD:-$(read_cloud)}"
SSH_CONFIG_OUT="${SSH_CONFIG_OUT:-$HOME/.ssh/${CLOUD}-multicloud-lab.generated}"
ANSIBLE_INVENTORY_OUT="${ANSIBLE_INVENTORY_OUT:-$ANSIBLE_DIR/inventory.cloud}"
SSH_INCLUDE="Include $SSH_CONFIG_OUT"

cd "$ROOT_DIR"
mkdir -p "$(dirname "$SSH_CONFIG_OUT")" "$ANSIBLE_DIR" "$HOME/.ssh"

touch "$HOME/.ssh/config"
terraform output -raw ssh_config > "$SSH_CONFIG_OUT"
terraform output -raw ansible_inventory > "$ANSIBLE_INVENTORY_OUT"

BASTION_ALIAS="$(awk '$0 == "[bastion]" { getline; split($1, host, " "); print host[1]; exit }' "$ANSIBLE_INVENTORY_OUT")"
if [ -n "$BASTION_ALIAS" ]; then
  sed -i "s/ansible_ssh_common_args=/coinops_ssh_common_args=/g" "$ANSIBLE_INVENTORY_OUT"
  sed -i -E "s/ProxyJump=[^ '\"]+/ProxyJump=${BASTION_ALIAS}/g" "$ANSIBLE_INVENTORY_OUT"
fi

tmp_config="$(mktemp)"
{
  printf '%s\n' "$SSH_INCLUDE"
  grep -Fvx "$SSH_INCLUDE" "$HOME/.ssh/config" | grep -Fvx "Include ~/.ssh/${CLOUD}-multicloud-lab.generated" || true
} > "$tmp_config"
cat "$tmp_config" > "$HOME/.ssh/config"
rm -f "$tmp_config"

echo "Wrote SSH config: $SSH_CONFIG_OUT"
echo "Prepended SSH include: $SSH_INCLUDE"
echo "Wrote Ansible inventory: $ANSIBLE_INVENTORY_OUT"
echo "App URL: $(terraform output -raw app_url)"

if [ "$RUN_ANSIBLE" = "true" ]; then
  : "${SSH_KEY_PATH:?Set SSH_KEY_PATH before RUN_ANSIBLE=true}"
  : "${DB_PASSWORD:?Set DB_PASSWORD before RUN_ANSIBLE=true}"
  : "${RABBITMQ_PASSWORD:?Set RABBITMQ_PASSWORD before RUN_ANSIBLE=true}"
  export RUNTIME_BACKEND="${RUNTIME_BACKEND:-external}"
  cd "$REPO_ROOT"
  ansible-playbook -i "$ANSIBLE_INVENTORY_OUT" ansible/cloud-provision.yml
  ansible-playbook -i "$ANSIBLE_INVENTORY_OUT" ansible/cloud-deploy.yml
else
  echo "To deploy app after apply:"
  echo "  cd $REPO_ROOT"
  echo "  export SSH_KEY_PATH=~/.ssh/coinops_gcp_jump"
  echo "  export DB_PASSWORD='...'"
  echo "  export RABBITMQ_PASSWORD='...'"
  echo "  export RUNTIME_BACKEND=external"
  echo "  ansible-playbook -i $ANSIBLE_INVENTORY_OUT ansible/cloud-provision.yml"
  echo "  ansible-playbook -i $ANSIBLE_INVENTORY_OUT ansible/cloud-deploy.yml"
  echo "Or run: RUN_ANSIBLE=true ./scripts/post-apply.sh"
fi