#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform.gcp.aws"
INVENTORY_PATH="${ROOT_DIR}/ansible/inventory.generated"
PROVISION_PLAYBOOK="${ROOT_DIR}/ansible/provision.yml"
DEPLOY_PLAYBOOK="${ROOT_DIR}/ansible/deploy.yml"
CLOUD_PROVIDER="${CLOUD_PROVIDER:-}"
AWS_SECRETS_ID="${AWS_SECRETS_ID:-coinops/app}"
AWS_SECRETS_REGION="${AWS_SECRETS_REGION:-${AWS_REGION:-eu-central-1}}"

export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-/tmp/ansible-local}"
export ANSIBLE_REMOTE_TEMP="${ANSIBLE_REMOTE_TEMP:-/tmp/ansible-remote}"

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

load_aws_secrets() {
  local secret_json

  require_command aws
  require_command jq

  secret_json="$(
    aws secretsmanager get-secret-value \
      --secret-id "${AWS_SECRETS_ID}" \
      --region "${AWS_SECRETS_REGION}" \
      --query SecretString \
      --output text
  )"

  if [[ -z "${secret_json}" || "${secret_json}" == "None" ]]; then
    echo "AWS Secrets Manager returned an empty secret for ${AWS_SECRETS_ID}" >&2
    exit 1
  fi

  export DB_PASSWORD="${DB_PASSWORD:-$(jq -r '.DB_PASSWORD // empty' <<<"${secret_json}")}"
  export RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-$(jq -r '.RABBITMQ_PASSWORD // empty' <<<"${secret_json}")}"
  export GHCR_USERNAME="${GHCR_USERNAME:-$(jq -r '.GHCR_USERNAME // empty' <<<"${secret_json}")}"
  export GHCR_TOKEN="${GHCR_TOKEN:-$(jq -r '.GHCR_TOKEN // empty' <<<"${secret_json}")}"
  export APP_DOMAIN="${APP_DOMAIN:-$(jq -r '.APP_DOMAIN // empty' <<<"${secret_json}")}"
  export TLS_MODE="${TLS_MODE:-$(jq -r '.TLS_MODE // empty' <<<"${secret_json}")}"
  export EXTERNAL_DB_HOST="${EXTERNAL_DB_HOST:-$(jq -r '.EXTERNAL_DB_HOST // empty' <<<"${secret_json}")}"
  export RUNTIME_BACKEND="${RUNTIME_BACKEND:-$(jq -r '.RUNTIME_BACKEND // empty' <<<"${secret_json}")}"
  export IMAGE_REGISTRY="${IMAGE_REGISTRY:-$(jq -r '.IMAGE_REGISTRY // empty' <<<"${secret_json}")}"
  export IMAGE_TAG="${IMAGE_TAG:-$(jq -r '.IMAGE_TAG // empty' <<<"${secret_json}")}"
  export IMAGE_SOURCE="${IMAGE_SOURCE:-$(jq -r '.IMAGE_SOURCE // empty' <<<"${secret_json}")}"
  export LOCAL_IMAGE_TAG="${LOCAL_IMAGE_TAG:-$(jq -r '.LOCAL_IMAGE_TAG // empty' <<<"${secret_json}")}"
  export LOCAL_IMAGE_ARTIFACT_DIR="${LOCAL_IMAGE_ARTIFACT_DIR:-$(jq -r '.LOCAL_IMAGE_ARTIFACT_DIR // empty' <<<"${secret_json}")}"
  export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-$(jq -r '.CLOUDFLARE_API_TOKEN // empty' <<<"${secret_json}")}"
  export TF_VAR_cloudflare_zone_name="${TF_VAR_cloudflare_zone_name:-$(jq -r '.TF_VAR_cloudflare_zone_name // empty' <<<"${secret_json}")}"
  export TF_VAR_cloudflare_account_id="${TF_VAR_cloudflare_account_id:-$(jq -r '.TF_VAR_cloudflare_account_id // empty' <<<"${secret_json}")}"
  export TF_VAR_cloudflare_record_name="${TF_VAR_cloudflare_record_name:-$(jq -r '.TF_VAR_cloudflare_record_name // empty' <<<"${secret_json}")}"
  export TF_VAR_cloudflare_proxied="${TF_VAR_cloudflare_proxied:-$(jq -r '.TF_VAR_cloudflare_proxied // empty' <<<"${secret_json}")}"
}

validate_local_context() {
  if [[ -z "${SSH_KEY_PATH:-}" ]]; then
    echo "SSH_KEY_PATH is required. Export it in the shell before running deploy.sh" >&2
    exit 1
  fi

  if [[ ! -f "${SSH_KEY_PATH}.pub" ]]; then
    echo "Missing public key: ${SSH_KEY_PATH}.pub" >&2
    exit 1
  fi

  export TF_VAR_ssh_public_key="${TF_VAR_ssh_public_key:-$(cat "${SSH_KEY_PATH}.pub")}"
}

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
  load_aws_secrets
  validate_local_context
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
