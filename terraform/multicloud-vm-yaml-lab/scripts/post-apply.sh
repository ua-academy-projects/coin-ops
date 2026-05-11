#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/../.." && pwd)"
ANSIBLE_DIR="$REPO_ROOT/ansible"
RUN_ANSIBLE="${RUN_ANSIBLE:-false}"

read_cloud() {
  awk -F: '/^cloud:[[:space:]]*/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$ROOT_DIR/config/lab.yaml"
}

read_runtime_mode() {
  awk '
    /^runtime:[[:space:]]*$/ { in_runtime=1; next }
    in_runtime && /^[^[:space:]]/ { in_runtime=0 }
    in_runtime && /^[[:space:]]+mode:[[:space:]]*/ { sub(/^[[:space:]]+mode:[[:space:]]*/, ""); gsub(/[[:space:]]/, ""); print; exit }
  ' "$ROOT_DIR/config/lab.yaml"
}

normalize_runtime_mode() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '-' '_'
}

expand_home_path() {
  path="$1"
  if [ "$path" = "~" ]; then
    printf '%s' "$HOME"
  elif [ "${path:0:2}" = "~/" ]; then
    printf '%s/%s' "$HOME" "${path:2}"
  else
    printf '%s' "$path"
  fi
}

refresh_lab_known_hosts() {
  known_hosts_file="$(awk '/^[[:space:]]*UserKnownHostsFile[[:space:]]+/ { print $2; exit }' "$SSH_CONFIG_OUT")"
  [ -n "$known_hosts_file" ] || return 0
  known_hosts_file="$(expand_home_path "$known_hosts_file")"
  mkdir -p "$(dirname "$known_hosts_file")"
  touch "$known_hosts_file"

  tmp_hosts="$(mktemp)"
  {
    awk '/^[[:space:]]*Host[[:space:]]+/ && $2 != "*" { print $2 }' "$SSH_CONFIG_OUT"
    awk '/^[[:space:]]*HostName[[:space:]]+/ { print $2 }' "$SSH_CONFIG_OUT"
    awk '
      /(^|[[:space:]])ansible_host=/ {
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^ansible_host=/) {
            sub(/^ansible_host=/, "", $i)
            print $i
          }
        }
      }
    ' "$ANSIBLE_INVENTORY_OUT"
  } | sort -u > "$tmp_hosts"

  while IFS= read -r host; do
    [ -n "$host" ] || continue
    ssh-keygen -f "$known_hosts_file" -R "$host" >/dev/null 2>&1 || true
    ssh-keygen -f "$known_hosts_file" -R "[$host]:22" >/dev/null 2>&1 || true
  done < "$tmp_hosts"
  rm -f "$tmp_hosts"

  echo "Refreshed lab known_hosts entries: $known_hosts_file"
}

ensure_inventory_known_hosts() {
  known_hosts_file="$(awk '/^[[:space:]]*UserKnownHostsFile[[:space:]]+/ { print $2; exit }' "$SSH_CONFIG_OUT")"
  [ -n "$known_hosts_file" ] || return 0

  tmp_inventory="$(mktemp)"
  awk -v known_hosts_file="$known_hosts_file" '
    /^coinops_ssh_common_args=/ && $0 !~ /UserKnownHostsFile=/ {
      sub(/StrictHostKeyChecking=accept-new/, "UserKnownHostsFile=" known_hosts_file " -o StrictHostKeyChecking=accept-new")
    }
    { print }
  ' "$ANSIBLE_INVENTORY_OUT" > "$tmp_inventory"
  cat "$tmp_inventory" > "$ANSIBLE_INVENTORY_OUT"
  rm -f "$tmp_inventory"
}

CLOUD="${CLOUD:-$(read_cloud)}"
RUNTIME_MODE="${RUNTIME_MODE:-$(read_runtime_mode)}"
RUNTIME_MODE="$(normalize_runtime_mode "${RUNTIME_MODE:-external}")"
SSH_CONFIG_OUT="${SSH_CONFIG_OUT:-$HOME/.ssh/${CLOUD}-multicloud-lab.generated}"
ANSIBLE_INVENTORY_OUT="${ANSIBLE_INVENTORY_OUT:-$ANSIBLE_DIR/inventory.cloud}"
SSH_INCLUDE="Include $SSH_CONFIG_OUT"

cd "$ROOT_DIR"
mkdir -p "$(dirname "$SSH_CONFIG_OUT")" "$ANSIBLE_DIR" "$HOME/.ssh"

touch "$HOME/.ssh/config"
terraform output -raw ssh_config > "$SSH_CONFIG_OUT"
terraform output -raw ansible_inventory > "$ANSIBLE_INVENTORY_OUT"
refresh_lab_known_hosts
ensure_inventory_known_hosts

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
  export RUNTIME_BACKEND="$RUNTIME_MODE"
  cd "$REPO_ROOT"
  ansible-playbook -i "$ANSIBLE_INVENTORY_OUT" ansible/cloud-provision.yml
  ansible-playbook -i "$ANSIBLE_INVENTORY_OUT" ansible/cloud-deploy.yml
else
  echo "To deploy app after apply:"
  echo "  cd $REPO_ROOT"
  echo "  export SSH_KEY_PATH=~/.ssh/coinops_gcp_jump"
  echo "  # secret values are fetched from cloud secret manager"
  echo "  # runtime comes from terraform/multicloud-vm-yaml-lab/config/lab.yaml"
  echo "  ansible-playbook -i $ANSIBLE_INVENTORY_OUT ansible/cloud-provision.yml"
  echo "  ansible-playbook -i $ANSIBLE_INVENTORY_OUT ansible/cloud-deploy.yml"
  echo "Or run: RUN_ANSIBLE=true ./scripts/post-apply.sh"
fi