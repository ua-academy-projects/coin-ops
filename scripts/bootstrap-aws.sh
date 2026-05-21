#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform.gcp.aws"
CONFIG_FILE="${TERRAFORM_DIR}/config.yml"
ENV_FILE="${ROOT_DIR}/.env"
BACKEND_FILE="${TERRAFORM_DIR}/backend.aws.hcl"

REQUIRED_SECRETS=(
  "coinops/db-password"
  "coinops/rabbitmq-password"
  "coinops/ghcr-token"
  "coinops/cloudflare-api-token"
)

log() {
  echo "[bootstrap-aws] $*"
}

fail() {
  echo "[bootstrap-aws] ERROR: $*" >&2
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

extract_aws_vm_types() {
  awk '
    $1 == "vms:" { in_vms=1; next }
    in_vms && /^[^[:space:]]/ && $1 != "vms:" { exit }
    in_vms && $1 == "machine_type:" { in_machine_type=1; next }
    in_vms && $1 == "image:" { in_machine_type=0; next }
    in_vms && in_machine_type && $1 == "aws:" {
      gsub(/"/, "", $2)
      print $2
    }
  ' "${CONFIG_FILE}" | sort -u
}

extract_aws_amis() {
  awk '
    $1 == "vms:" { in_vms=1; next }
    in_vms && /^[^[:space:]]/ && $1 != "vms:" { exit }
    in_vms && $1 == "image:" { in_image=1; next }
    in_vms && $1 == "ip:" { in_image=0; next }
    in_vms && in_image && $1 == "aws:" {
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
  require_command aws
  require_command terraform
  require_command ansible-playbook
  require_command jq
  require_command curl
}

load_config() {
  AWS_REGION_CONFIG="$(extract_config_value "aws" "region")"
  AWS_PUBLIC_KEY_PATH="$(awk '$1=="public_key_path:" {print $2; exit}' "${CONFIG_FILE}")"
  BACKEND_BUCKET="$(extract_backend_value "bucket")"
  BACKEND_REGION="$(extract_backend_value "region")"
  BACKEND_LOCK_TABLE="$(extract_backend_value "dynamodb_table")"

  [[ -n "${AWS_REGION_CONFIG}" ]] || fail "Missing project.aws.region in ${CONFIG_FILE}"
  [[ -n "${BACKEND_BUCKET}" ]] || fail "Missing bucket in ${BACKEND_FILE}"
  [[ -n "${BACKEND_REGION}" ]] || fail "Missing region in ${BACKEND_FILE}"
  [[ -n "${BACKEND_LOCK_TABLE}" ]] || fail "Missing dynamodb_table in ${BACKEND_FILE}"

  export AWS_REGION="${AWS_REGION:-${AWS_REGION_CONFIG}}"
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-${AWS_REGION}}"
}

check_aws_login() {
  log "Checking AWS credentials"
  aws sts get-caller-identity >/dev/null 2>&1 || fail \
    "AWS credentials are not valid. Check AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY or AWS profile"
}

check_aws_region() {
  local current_region
  current_region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
  [[ "${current_region}" == "${AWS_REGION_CONFIG}" ]] || fail \
    "Active AWS region ${current_region:-<empty>} does not match config ${AWS_REGION_CONFIG}"
}

check_aws_secrets() {
  log "Checking required Secrets Manager secrets"

  local secret
  for secret in "${REQUIRED_SECRETS[@]}"; do
    aws secretsmanager get-secret-value \
      --secret-id "${secret}" \
      --region "${AWS_REGION}" \
      --query SecretString \
      --output text >/dev/null 2>&1 || fail \
      "Missing or unreadable Secrets Manager secret: ${secret}"
  done
}

check_ssh_key() {
  local public_key_path

  public_key_path="$(eval echo "${AWS_PUBLIC_KEY_PATH}")"
  [[ -f "${public_key_path}" ]] || fail "SSH public key not found: ${public_key_path}"

  if [[ -n "${SSH_KEY_PATH:-}" ]]; then
    [[ -f "${SSH_KEY_PATH}" ]] || fail "SSH private key not found: ${SSH_KEY_PATH}"
  fi
}

check_aws_instance_types() {
  log "Checking AWS instance types from config"

  local instance_type
  while IFS= read -r instance_type; do
    [[ -n "${instance_type}" ]] || continue

    aws ec2 describe-instance-types \
      --instance-types "${instance_type}" \
      --region "${AWS_REGION}" >/dev/null 2>&1 || fail \
      "AWS instance type ${instance_type} is not available in ${AWS_REGION}"
  done < <(extract_aws_vm_types)
}

check_aws_amis() {
  log "Checking AWS AMIs from config"

  local ami
  while IFS= read -r ami; do
    [[ -n "${ami}" ]] || continue

    aws ec2 describe-images \
      --image-ids "${ami}" \
      --region "${AWS_REGION}" \
      --query 'Images[0].ImageId' \
      --output text 2>/dev/null | grep -qx "${ami}" || fail \
      "AWS AMI ${ami} is not readable in ${AWS_REGION}"
  done < <(extract_aws_amis)
}

check_backend_access() {
  log "Checking S3 backend resources"
  aws s3api head-bucket --bucket "${BACKEND_BUCKET}" >/dev/null 2>&1 || fail \
    "Cannot access backend bucket ${BACKEND_BUCKET}"
  aws dynamodb describe-table \
    --table-name "${BACKEND_LOCK_TABLE}" \
    --region "${BACKEND_REGION}" >/dev/null 2>&1 || fail \
    "Cannot access backend lock table ${BACKEND_LOCK_TABLE} in ${BACKEND_REGION}"
}

terraform_init() {
  log "Running Terraform init for AWS backend"
  terraform -chdir="${TERRAFORM_DIR}" init -reconfigure -backend-config="${BACKEND_FILE}" >/dev/null
}

print_summary() {
  cat <<EOF

AWS bootstrap: ok
  Region       : ${AWS_REGION}
  Backend      : s3://${BACKEND_BUCKET}

Next step:
  source .env
  CLOUD_PROVIDER=aws ./deploy.sh all
EOF
}

main() {
  check_tools
  load_env
  load_config
  check_aws_login
  check_aws_region
  check_aws_secrets
  check_ssh_key
  check_aws_instance_types
  check_aws_amis
  check_backend_access
  terraform_init
  print_summary
}

main "$@"
