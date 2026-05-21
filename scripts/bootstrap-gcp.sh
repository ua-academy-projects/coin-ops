#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform.gcp.aws"
CONFIG_FILE="${TERRAFORM_DIR}/config.yml"
ENV_FILE="${ROOT_DIR}/.env"
BACKEND_FILE="${TERRAFORM_DIR}/backend.gcp.hcl"

REQUIRED_SECRETS=(
  "coinops-db-password"
  "coinops-rabbitmq-password"
  "coinops-ghcr-token"
  "coinops-cloudflare-api-token"
)

REQUIRED_SERVICES=(
  "compute.googleapis.com"
  "secretmanager.googleapis.com"
)

log() {
  echo "[bootstrap-gcp] $*"
}

fail() {
  echo "[bootstrap-gcp] ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

extract_config_value() {
  local section="$1"
  local key="$2"

  awk -v section="${section}" -v key="${key}" '
    $1 == section ":" { in_section=1; next }
    in_section && $1 == key ":" {
      value=$0
      sub(/^[^:]+:[[:space:]]*/, "", value)
      gsub(/"/, "", value)
      print value
      exit
    }
    in_section && /^[^[:space:]]/ { exit }
  ' "${CONFIG_FILE}"
}

extract_gcp_vm_types() {
  awk '
    $1 == "vms:" { in_vms=1; next }
    in_vms && /^[^[:space:]]/ && $1 != "vms:" { exit }
    in_vms && $1 == "machine_type:" { in_machine_type=1; next }
    in_vms && $1 == "image:" { in_machine_type=0; next }
    in_vms && in_machine_type && $1 == "gcp:" {
      gsub(/"/, "", $2)
      print $2
    }
  ' "${CONFIG_FILE}" | sort -u
}

extract_backend_value() {
  local key="$1"
  awk -F'=' -v key="${key}" '
    $1 ~ key {
      value=$2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/"/, "", value)
      print value
      exit
    }
  ' "${BACKEND_FILE}"
}

load_env() {
  if [[ -f "${ENV_FILE}" ]]; then
    set -a
    . "${ENV_FILE}"
    set +a
  fi
}

check_tools() {
  log "Checking local tools"
  require_command gcloud
  require_command aws
  require_command terraform
  require_command ansible-playbook
  require_command jq
  require_command curl
}

load_config() {
  GCP_PROJECT_ID="$(extract_config_value "gcp" "id")"
  GCP_REGION="$(extract_config_value "gcp" "region")"
  GCP_ZONE="$(extract_config_value "gcp" "zone")"
  GCP_PUBLIC_KEY_PATH="$(awk '$1=="public_key_path:" {print $2; exit}' "${CONFIG_FILE}")"
  BACKEND_BUCKET="$(extract_backend_value "bucket")"
  BACKEND_REGION="$(extract_backend_value "region")"
  BACKEND_LOCK_TABLE="$(extract_backend_value "dynamodb_table")"

  [[ -n "${GCP_PROJECT_ID}" ]] || fail "Missing project.gcp.id in ${CONFIG_FILE}"
  [[ -n "${GCP_REGION}" ]] || fail "Missing project.gcp.region in ${CONFIG_FILE}"
  [[ -n "${GCP_ZONE}" ]] || fail "Missing project.gcp.zone in ${CONFIG_FILE}"
  [[ -n "${BACKEND_BUCKET}" ]] || fail "Missing bucket in ${BACKEND_FILE}"
  [[ -n "${BACKEND_REGION}" ]] || fail "Missing region in ${BACKEND_FILE}"
  [[ -n "${BACKEND_LOCK_TABLE}" ]] || fail "Missing dynamodb_table in ${BACKEND_FILE}"
}

check_gcp_login() {
  log "Checking GCP login"
  gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q . || fail \
    "GCloud CLI is not logged in. Run: gcloud auth login"
}

check_gcp_project() {
  local current_project
  current_project="$(gcloud config get-value project 2>/dev/null | tr -d '[:space:]')"

  [[ "${current_project}" == "${GCP_PROJECT_ID}" ]] || fail \
    "Active gcloud project ${current_project:-<empty>} does not match config ${GCP_PROJECT_ID}"
}

ensure_service_enabled() {
  local service="$1"

  if ! gcloud services list --enabled --filter="config.name=${service}" --format="value(config.name)" | grep -qx "${service}"; then
    log "Enabling GCP service ${service}"
    gcloud services enable "${service}" --project="${GCP_PROJECT_ID}" >/dev/null
  else
    log "Service ${service} already enabled"
  fi
}

check_gcp_services() {
  log "Checking required GCP APIs"
  local service
  for service in "${REQUIRED_SERVICES[@]}"; do
    ensure_service_enabled "${service}"
  done
}

check_gcp_secrets() {
  log "Checking required Secret Manager secrets"

  local secret
  for secret in "${REQUIRED_SECRETS[@]}"; do
    gcloud secrets versions access latest \
      --secret="${secret}" \
      --project="${GCP_PROJECT_ID}" >/dev/null 2>&1 || fail \
      "Missing or unreadable Secret Manager secret: ${secret}"
  done
}

check_ssh_key() {
  local public_key_path

  public_key_path="$(eval echo "${GCP_PUBLIC_KEY_PATH}")"
  [[ -f "${public_key_path}" ]] || fail "SSH public key not found: ${public_key_path}"

  if [[ -n "${SSH_KEY_PATH:-}" ]]; then
    [[ -f "${SSH_KEY_PATH}" ]] || fail "SSH private key not found: ${SSH_KEY_PATH}"
  fi
}

check_gcp_vm_types() {
  log "Checking GCP machine types from config"

  local machine_type
  while IFS= read -r machine_type; do
    [[ -n "${machine_type}" ]] || continue

    gcloud compute machine-types describe "${machine_type}" \
      --zone "${GCP_ZONE}" \
      --project "${GCP_PROJECT_ID}" >/dev/null 2>&1 || fail \
      "GCP machine type ${machine_type} is not available in zone ${GCP_ZONE}"
  done < <(extract_gcp_vm_types)
}

check_aws_backend_access() {
  log "Checking AWS backend access for Terraform state"
  aws sts get-caller-identity >/dev/null 2>&1 || fail "AWS credentials are not valid for S3 backend access"
  aws s3api head-bucket --bucket "${BACKEND_BUCKET}" >/dev/null 2>&1 || fail \
    "Cannot access backend bucket ${BACKEND_BUCKET}"
  aws dynamodb describe-table \
    --table-name "${BACKEND_LOCK_TABLE}" \
    --region "${BACKEND_REGION}" >/dev/null 2>&1 || fail \
    "Cannot access backend lock table ${BACKEND_LOCK_TABLE} in ${BACKEND_REGION}"
}

terraform_init() {
  log "Running Terraform init for GCP backend"
  terraform -chdir="${TERRAFORM_DIR}" init -reconfigure -backend-config="${BACKEND_FILE}" >/dev/null
}

print_summary() {
  cat <<EOF

GCP bootstrap: ok
  Project      : ${GCP_PROJECT_ID}
  Region       : ${GCP_REGION}
  Zone         : ${GCP_ZONE}
  Backend      : s3://${BACKEND_BUCKET}

Next step:
  source .env
  CLOUD_PROVIDER=gcp ./deploy.sh all
EOF
}

main() {
  check_tools
  load_env
  load_config
  check_gcp_login
  check_gcp_project
  check_gcp_services
  check_gcp_secrets
  check_ssh_key
  check_gcp_vm_types
  check_aws_backend_access
  terraform_init
  print_summary
}

main "$@"
