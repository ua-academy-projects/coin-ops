#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/../.." && pwd)"
ANSIBLE_INVENTORY_OUT="${ANSIBLE_INVENTORY_OUT:-$REPO_ROOT/ansible/inventory.cloud}"
BACKEND_CONFIG="${BACKEND_CONFIG:-backend.hcl}"
AUTO_APPROVE="${AUTO_APPROVE:-false}"
LOAD_ENV="${LOAD_ENV:-true}"

read_cloud() {
  awk -F: '/^cloud:[[:space:]]*/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$ROOT_DIR/config/lab.yaml"
}

CLOUD="${CLOUD:-$(read_cloud)}"

usage() {
  cat <<USAGE
Usage: ./scripts/lab.sh <command>

Commands:
  init       terraform init + select/create workspace from config/lab.yaml cloud
  plan       init, then terraform plan
  apply      init, terraform apply, then regenerate SSH config + Ansible inventory
  outputs    regenerate SSH config + Ansible inventory from current Terraform outputs
  ping       ansible ping all cloud hosts through generated inventory
  deploy     run Ansible provision + deploy using generated inventory
  full       apply, regenerate outputs, then deploy

Useful env vars:
  AUTO_APPROVE=true       pass -auto-approve to terraform apply
  LOAD_ENV=false          do not source repo .env if present
  SSH_KEY_PATH=...        required for deploy
  DB_PASSWORD=...         required for deploy
  RABBITMQ_PASSWORD=...   required for deploy
  RUNTIME_BACKEND=external

Examples:
  ./scripts/lab.sh plan
  AUTO_APPROVE=true ./scripts/lab.sh apply
  SSH_KEY_PATH=~/.ssh/coinops_gcp_jump DB_PASSWORD=... RABBITMQ_PASSWORD=... ./scripts/lab.sh deploy
  AUTO_APPROVE=true SSH_KEY_PATH=~/.ssh/coinops_gcp_jump DB_PASSWORD=... RABBITMQ_PASSWORD=... ./scripts/lab.sh full
USAGE
}

load_env_file() {
  if [ "$LOAD_ENV" = "true" ] && [ -f "$REPO_ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$REPO_ROOT/.env"
    set +a
  fi
}

terraform_init() {
  cd "$ROOT_DIR"
  terraform init -backend-config="$BACKEND_CONFIG" -reconfigure
  terraform workspace select "$CLOUD" || terraform workspace new "$CLOUD"
}

terraform_apply() {
  cd "$ROOT_DIR"
  if [ "$AUTO_APPROVE" = "true" ]; then
    terraform apply -auto-approve
  else
    terraform apply
  fi
}

write_outputs() {
  cd "$ROOT_DIR"
  CLOUD="$CLOUD" "$ROOT_DIR/scripts/post-apply.sh"
}

ansible_deploy() {
  load_env_file
  : "${SSH_KEY_PATH:?Set SSH_KEY_PATH or put it in .env}"
  : "${DB_PASSWORD:?Set DB_PASSWORD or put it in .env}"
  : "${RABBITMQ_PASSWORD:?Set RABBITMQ_PASSWORD or put it in .env}"
  export RUNTIME_BACKEND="${RUNTIME_BACKEND:-external}"
  cd "$REPO_ROOT"
  ansible-playbook -i "$ANSIBLE_INVENTORY_OUT" ansible/cloud-provision.yml
  ansible-playbook -i "$ANSIBLE_INVENTORY_OUT" ansible/cloud-deploy.yml
}

cmd="${1:-}"
case "$cmd" in
  init)
    terraform_init
    ;;
  plan)
    terraform_init
    cd "$ROOT_DIR"
    terraform plan
    ;;
  apply)
    terraform_init
    terraform_apply
    write_outputs
    ;;
  outputs)
    write_outputs
    ;;
  ping)
    cd "$REPO_ROOT"
    ansible -i "$ANSIBLE_INVENTORY_OUT" all -m ping
    ;;
  deploy)
    ansible_deploy
    ;;
  full)
    terraform_init
    terraform_apply
    write_outputs
    ansible_deploy
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac