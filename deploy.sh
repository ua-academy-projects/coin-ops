#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform.gcp.aws"
INVENTORY_PATH="${ROOT_DIR}/ansible/inventory.generated"
PROVISION_PLAYBOOK="${ROOT_DIR}/ansible/provision.yml"
DEPLOY_PLAYBOOK="${ROOT_DIR}/ansible/deploy.yml"
CLOUD_PROVIDER="${CLOUD_PROVIDER:-}"

if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  echo "Missing .env in ${ROOT_DIR}" >&2
  exit 1
fi

set -a
. "${ROOT_DIR}/.env"
set +a

export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-/tmp/ansible-local}"
export ANSIBLE_REMOTE_TEMP="${ANSIBLE_REMOTE_TEMP:-/tmp/ansible-remote}"

resolve_cloud_provider() {
  if [[ -n "${CLOUD_PROVIDER}" ]]; then
    return
  fi

  CLOUD_PROVIDER="$(
    awk '
      $0 ~ /^variable "cloud"/ { in_block=1; next }
      in_block && $1 == "default" {
        gsub(/"/, "", $3)
        print $3
        exit
      }
      in_block && $0 ~ /^}/ { exit }
    ' "${TERRAFORM_DIR}/variables.tf"
  )"

  if [[ -z "${CLOUD_PROVIDER}" ]]; then
    echo "Unable to resolve cloud provider from ${TERRAFORM_DIR}/variables.tf" >&2
    exit 1
  fi
}

prepare_cloud_env() {
  resolve_cloud_provider

  case "${CLOUD_PROVIDER}" in
    aws)
      export TF_VAR_db_password="${TF_VAR_db_password:-${DB_PASSWORD:-}}"
      ;;
    gcp)
      unset EXTERNAL_DB_HOST
      unset TF_VAR_db_password
      ;;
    *)
      echo "Unsupported CLOUD_PROVIDER: ${CLOUD_PROVIDER}" >&2
      exit 1
      ;;
  esac
}

run_terraform_init() {
  terraform -chdir="${TERRAFORM_DIR}" init
}

run_infra() {
  terraform -chdir="${TERRAFORM_DIR}" apply -var="cloud=${CLOUD_PROVIDER}" -auto-approve
}

run_provision() {
  ansible-playbook -i "${INVENTORY_PATH}" "${PROVISION_PLAYBOOK}"
}

run_deploy() {
  ansible-playbook -i "${INVENTORY_PATH}" "${DEPLOY_PLAYBOOK}"
}

print_status_link() {
  local lb_dns lb_ip target

  lb_dns="$(terraform -chdir="${TERRAFORM_DIR}" output -raw load_balancer_dns_name 2>/dev/null || true)"
  lb_ip="$(terraform -chdir="${TERRAFORM_DIR}" output -raw load_balancer_ip_address 2>/dev/null || true)"

  if [[ -n "${lb_dns}" && "${lb_dns}" != "null" ]]; then
    target="http://${lb_dns}"
  elif [[ -n "${lb_ip}" && "${lb_ip}" != "null" ]]; then
    target="http://${lb_ip}"
  else
    target="load balancer output is unavailable"
  fi

  echo
  echo "Your Application has deployed succesfully. To check status follow the link:"
  echo "https://app.smolyakov-devops.pp.ua"
}

case "${1:-all}" in
  infra)
    prepare_cloud_env
    run_terraform_init
    run_infra
    ;;
  provision)
    prepare_cloud_env
    run_provision
    print_status_link
    ;;
  deploy)
    prepare_cloud_env
    run_deploy
    print_status_link
    ;;
  all)
    prepare_cloud_env
    run_terraform_init
    run_infra
    run_provision
    run_deploy
    print_status_link
    ;;
  *)
    echo "Usage: $0 [infra|provision|deploy|all]" >&2
    exit 1
    ;;
esac
