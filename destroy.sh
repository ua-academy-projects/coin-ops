#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform.gcp.aws"
CLOUD_PROVIDER="${CLOUD_PROVIDER:-}"
SSH_ALLOWED_SOURCE_CIDR_OVERRIDE="${SSH_ALLOWED_SOURCE_CIDR:-}"
AWS_REGION_FROM_CONFIG=""
GCP_PROJECT_ID_FROM_CONFIG=""
AZURE_KEY_VAULT_NAME_FROM_CONFIG=""

if [[ ! -f "${ROOT_DIR}/.env" ]]; then
  echo "Missing .env in ${ROOT_DIR}" >&2
  exit 1
fi

set -a
. "${ROOT_DIR}/.env"
set +a

if [[ -n "${SSH_ALLOWED_SOURCE_CIDR_OVERRIDE}" ]]; then
  export SSH_ALLOWED_SOURCE_CIDR="${SSH_ALLOWED_SOURCE_CIDR_OVERRIDE}"
fi

resolve_cloud_provider() {
  if [[ -n "${CLOUD_PROVIDER}" ]]; then
    return
  fi

  CLOUD_PROVIDER="$({
    awk '
      $0 ~ /^variable "cloud"/ { in_block=1; next }
      in_block && $1 == "default" {
        gsub(/"/, "", $3)
        print $3
        exit
      }
      in_block && $0 ~ /^}/ { exit }
    ' "${TERRAFORM_DIR}/variables.tf"
  })"

  if [[ -z "${CLOUD_PROVIDER}" ]]; then
    echo "Unable to resolve cloud provider from ${TERRAFORM_DIR}/variables.tf" >&2
    exit 1
  fi
}

resolve_aws_region() {
  if [[ -n "${AWS_REGION:-}" ]]; then
    AWS_REGION_FROM_CONFIG="${AWS_REGION}"
    export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-${AWS_REGION}}"
    return
  fi

  AWS_REGION_FROM_CONFIG="$(
    awk '
      $1 == "aws:" { in_aws=1; next }
      in_aws && $1 == "region:" { gsub(/"/, "", $2); print $2; exit }
      in_aws && /^[^[:space:]]/ { exit }
    ' "${TERRAFORM_DIR}/config.yml"
  )"

  if [[ -n "${AWS_REGION_FROM_CONFIG}" ]]; then
    export AWS_REGION="${AWS_REGION_FROM_CONFIG}"
    export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-${AWS_REGION_FROM_CONFIG}}"
  fi
}

resolve_gcp_project_id() {
  if [[ -n "${GOOGLE_CLOUD_PROJECT:-}" ]]; then
    GCP_PROJECT_ID_FROM_CONFIG="${GOOGLE_CLOUD_PROJECT}"
    return
  fi

  GCP_PROJECT_ID_FROM_CONFIG="$(
    awk '
      $1 == "gcp:" { in_gcp=1; next }
      in_gcp && $1 == "id:" { gsub(/"/, "", $2); print $2; exit }
      in_gcp && /^[^[:space:]]/ { exit }
    ' "${TERRAFORM_DIR}/config.yml"
  )"

  if [[ -n "${GCP_PROJECT_ID_FROM_CONFIG}" ]]; then
    export GOOGLE_CLOUD_PROJECT="${GCP_PROJECT_ID_FROM_CONFIG}"
  fi
}

resolve_azure_key_vault_name() {
  if [[ -n "${AZURE_KEY_VAULT_NAME:-}" ]]; then
    AZURE_KEY_VAULT_NAME_FROM_CONFIG="${AZURE_KEY_VAULT_NAME}"
    return
  fi

  AZURE_KEY_VAULT_NAME_FROM_CONFIG="$(
    awk '
      $1 == "azure:" { in_azure=1; next }
      in_azure && $1 == "key_vault_name:" { gsub(/"/, "", $2); print $2; exit }
      in_azure && /^[^[:space:]]/ { exit }
    ' "${TERRAFORM_DIR}/config.yml"
  )"

  if [[ -n "${AZURE_KEY_VAULT_NAME_FROM_CONFIG}" ]]; then
    export AZURE_KEY_VAULT_NAME="${AZURE_KEY_VAULT_NAME_FROM_CONFIG}"
  fi
}

read_aws_secret() {
  local secret_id="$1"

  aws secretsmanager get-secret-value \
    --secret-id "${secret_id}" \
    --region "${AWS_REGION_FROM_CONFIG}" \
    --query SecretString \
    --output text
}

read_gcp_secret() {
  local secret_id="$1"

  gcloud secrets versions access latest \
    --secret="${secret_id}" \
    --project="${GCP_PROJECT_ID_FROM_CONFIG}"
}

read_azure_secret() {
  local secret_id="$1"

  az keyvault secret show \
    --vault-name "${AZURE_KEY_VAULT_NAME_FROM_CONFIG}" \
    --name "${secret_id}" \
    --query value \
    -o tsv
}

load_aws_secrets() {
  resolve_aws_region

  if [[ -z "${AWS_REGION_FROM_CONFIG}" ]]; then
    echo "Unable to resolve AWS region for Secrets Manager access" >&2
    exit 1
  fi

  export DB_PASSWORD="${DB_PASSWORD:-$(read_aws_secret "${AWS_SECRET_DB_PASSWORD_ID:-coinops/db-password}")}"
  export RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-$(read_aws_secret "${AWS_SECRET_RABBITMQ_PASSWORD_ID:-coinops/rabbitmq-password}")}"
  export GHCR_TOKEN="${GHCR_TOKEN:-$(read_aws_secret "${AWS_SECRET_GHCR_TOKEN_ID:-coinops/ghcr-token}")}"
  export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-$(read_aws_secret "${AWS_SECRET_CLOUDFLARE_TOKEN_ID:-coinops/cloudflare-api-token}")}"
}

load_gcp_secrets() {
  resolve_gcp_project_id

  if [[ -z "${GCP_PROJECT_ID_FROM_CONFIG}" ]]; then
    echo "Unable to resolve GCP project id for Secret Manager access" >&2
    exit 1
  fi

  export DB_PASSWORD="${DB_PASSWORD:-$(read_gcp_secret "${GCP_SECRET_DB_PASSWORD_ID:-coinops-db-password}")}"
  export RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-$(read_gcp_secret "${GCP_SECRET_RABBITMQ_PASSWORD_ID:-coinops-rabbitmq-password}")}"
  export GHCR_TOKEN="${GHCR_TOKEN:-$(read_gcp_secret "${GCP_SECRET_GHCR_TOKEN_ID:-coinops-ghcr-token}")}"
  export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-$(read_gcp_secret "${GCP_SECRET_CLOUDFLARE_TOKEN_ID:-coinops-cloudflare-api-token}")}"
}

load_azure_secrets() {
  resolve_azure_key_vault_name

  if [[ -z "${AZURE_KEY_VAULT_NAME_FROM_CONFIG}" ]]; then
    echo "Unable to resolve Azure Key Vault name for secret access" >&2
    exit 1
  fi

  export DB_PASSWORD="${DB_PASSWORD:-$(read_azure_secret "${AZURE_SECRET_DB_PASSWORD_ID:-coinops-db-password}")}"
  export RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-$(read_azure_secret "${AZURE_SECRET_RABBITMQ_PASSWORD_ID:-coinops-rabbitmq-password}")}"
  export GHCR_TOKEN="${GHCR_TOKEN:-$(read_azure_secret "${AZURE_SECRET_GHCR_TOKEN_ID:-coinops-ghcr-token}")}"
  export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-$(read_azure_secret "${AZURE_SECRET_CLOUDFLARE_TOKEN_ID:-coinops-cloudflare-api-token}")}"
}

resolve_ssh_allowed_source_cidr() {
  if [[ -n "${SSH_ALLOWED_SOURCE_CIDR:-}" ]]; then
    export TF_VAR_ssh_allowed_source_cidr="${SSH_ALLOWED_SOURCE_CIDR}"
    return
  fi

  local public_ip
  public_ip="$(curl -fsS -4 https://ifconfig.me 2>/dev/null || true)"

  if [[ -n "${public_ip}" ]]; then
    export TF_VAR_ssh_allowed_source_cidr="${public_ip}/32"
  fi
}

prepare_cloud_env() {
  resolve_cloud_provider

  case "${CLOUD_PROVIDER}" in
    aws)
      load_aws_secrets
      ;;
    gcp)
      load_gcp_secrets
      ;;
    azure)
      load_azure_secrets
      ;;
    *)
      echo "Unsupported CLOUD_PROVIDER: ${CLOUD_PROVIDER}" >&2
      exit 1
      ;;
  esac

  export TF_VAR_db_password="${TF_VAR_db_password:-${DB_PASSWORD:-}}"
  resolve_ssh_allowed_source_cidr
}

resolve_backend_config() {
  case "${CLOUD_PROVIDER}" in
    aws)
      echo "${TERRAFORM_DIR}/backend.aws.hcl"
      ;;
    gcp)
      echo "${TERRAFORM_DIR}/backend.gcp.hcl"
      ;;
    azure)
      echo "${TERRAFORM_DIR}/backend.azure.hcl"
      ;;
    *)
      echo "Unsupported CLOUD_PROVIDER: ${CLOUD_PROVIDER}" >&2
      exit 1
      ;;
  esac
}

run_terraform_init() {
  local backend_config
  backend_config="$(resolve_backend_config)"

  terraform -chdir="${TERRAFORM_DIR}" init -reconfigure -backend-config="${backend_config}"
}

run_destroy() {
  terraform -chdir="${TERRAFORM_DIR}" destroy -var="cloud=${CLOUD_PROVIDER}" "$@"
}

prepare_cloud_env
run_terraform_init
run_destroy "$@"
