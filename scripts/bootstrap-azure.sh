#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="${ROOT_DIR}/terraform.gcp.aws"
CONFIG_FILE="${TERRAFORM_DIR}/config.yml"
ENV_FILE="${ROOT_DIR}/.env"
BACKEND_FILE="${TERRAFORM_DIR}/backend.azure.hcl"

REQUIRED_SECRETS=(
  "coinops-db-password"
  "coinops-rabbitmq-password"
  "coinops-ghcr-token"
  "coinops-cloudflare-api-token"
)

log() {
  echo "[bootstrap-azure] $*"
}

fail() {
  echo "[bootstrap-azure] ERROR: $*" >&2
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

extract_azure_vm_sizes() {
  awk '
    $1 == "vms:" { in_vms=1; next }
    in_vms && /^[^[:space:]]/ && $1 != "vms:" { exit }
    in_vms && $1 == "azure:" {
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
  require_command az
  require_command aws
  require_command terraform
  require_command ansible-playbook
  require_command jq
  require_command curl
}

load_config() {
  AZURE_SUBSCRIPTION_ID="$(extract_config_value "azure" "subscription_id")"
  AZURE_TENANT_ID="$(extract_config_value "azure" "tenant_id")"
  AZURE_LOCATION="$(extract_config_value "azure" "location")"
  AZURE_KEY_VAULT_NAME="${AZURE_KEY_VAULT_NAME:-$(extract_config_value "azure" "key_vault_name")}"
  AZURE_RESOURCE_GROUP_NAME="$(extract_config_value "azure" "resource_group_name")"
  AZURE_USE_EXISTING_RG="$(extract_config_value "azure" "use_existing_resource_group")"
  AZURE_PUBLIC_KEY_PATH="$(awk '$1=="public_key_path:" {print $2; exit}' "${CONFIG_FILE}")"
  BACKEND_BUCKET="$(extract_backend_value "bucket")"
  BACKEND_REGION="$(extract_backend_value "region")"
  BACKEND_LOCK_TABLE="$(extract_backend_value "dynamodb_table")"

  [[ -n "${AZURE_SUBSCRIPTION_ID}" ]] || fail "Missing project.azure.subscription_id in ${CONFIG_FILE}"
  [[ -n "${AZURE_TENANT_ID}" ]] || fail "Missing project.azure.tenant_id in ${CONFIG_FILE}"
  [[ -n "${AZURE_LOCATION}" ]] || fail "Missing project.azure.location in ${CONFIG_FILE}"
  [[ -n "${AZURE_KEY_VAULT_NAME}" ]] || fail "Missing project.azure.key_vault_name in ${CONFIG_FILE}"
  [[ -n "${AZURE_RESOURCE_GROUP_NAME}" ]] || fail "Missing project.azure.resource_group_name in ${CONFIG_FILE}"
  [[ -n "${BACKEND_BUCKET}" ]] || fail "Missing bucket in ${BACKEND_FILE}"
  [[ -n "${BACKEND_REGION}" ]] || fail "Missing region in ${BACKEND_FILE}"
  [[ -n "${BACKEND_LOCK_TABLE}" ]] || fail "Missing dynamodb_table in ${BACKEND_FILE}"
}

check_azure_login() {
  log "Checking Azure login"
  az account show >/dev/null 2>&1 || fail "Azure CLI is not logged in. Run: az login"
}

check_azure_subscription() {
  local current_subscription current_tenant
  current_subscription="$(az account show --query id -o tsv)"
  current_tenant="$(az account show --query tenantId -o tsv)"

  [[ "${current_subscription}" == "${AZURE_SUBSCRIPTION_ID}" ]] || fail \
    "Active Azure subscription ${current_subscription} does not match config ${AZURE_SUBSCRIPTION_ID}"

  [[ "${current_tenant}" == "${AZURE_TENANT_ID}" ]] || fail \
    "Active Azure tenant ${current_tenant} does not match config ${AZURE_TENANT_ID}"
}

ensure_provider_registered() {
  local namespace="$1"
  local state

  state="$(az provider show --namespace "${namespace}" --query registrationState -o tsv)"
  if [[ "${state}" != "Registered" ]]; then
    log "Registering Azure provider ${namespace}"
    az provider register --namespace "${namespace}" >/dev/null
  else
    log "Provider ${namespace} already registered"
  fi
}

check_azure_providers() {
  log "Checking Azure provider registrations"
  ensure_provider_registered "Microsoft.Network"
  ensure_provider_registered "Microsoft.Compute"
  ensure_provider_registered "Microsoft.DBforPostgreSQL"
  ensure_provider_registered "Microsoft.Storage"
  ensure_provider_registered "Microsoft.KeyVault"
}

check_resource_group() {
  log "Checking Azure resource group ${AZURE_RESOURCE_GROUP_NAME}"

  if [[ "${AZURE_USE_EXISTING_RG}" != "true" ]]; then
    fail "This bootstrap expects project.azure.use_existing_resource_group=true"
  fi

  az group show --name "${AZURE_RESOURCE_GROUP_NAME}" >/dev/null 2>&1 || fail \
    "Resource group ${AZURE_RESOURCE_GROUP_NAME} does not exist"

  local actual_location
  actual_location="$(az group show --name "${AZURE_RESOURCE_GROUP_NAME}" --query location -o tsv)"
  log "Existing RG location: ${actual_location}"
}

check_key_vault() {
  log "Checking Azure Key Vault ${AZURE_KEY_VAULT_NAME}"
  az keyvault show --name "${AZURE_KEY_VAULT_NAME}" >/dev/null 2>&1 || fail \
    "Key Vault ${AZURE_KEY_VAULT_NAME} does not exist or is not accessible"
}

check_key_vault_secrets() {
  log "Checking required Key Vault secrets"

  local secret
  for secret in "${REQUIRED_SECRETS[@]}"; do
    az keyvault secret show \
      --vault-name "${AZURE_KEY_VAULT_NAME}" \
      --name "${secret}" \
      --query id \
      -o tsv >/dev/null 2>&1 || fail "Missing or unreadable Key Vault secret: ${secret}"
  done
}

check_ssh_key() {
  local public_key_path

  public_key_path="$(eval echo "${AZURE_PUBLIC_KEY_PATH}")"
  [[ -f "${public_key_path}" ]] || fail "SSH public key not found: ${public_key_path}"

  if [[ -n "${SSH_KEY_PATH:-}" ]]; then
    [[ -f "${SSH_KEY_PATH}" ]] || fail "SSH private key not found: ${SSH_KEY_PATH}"
  fi
}

check_azure_vm_skus() {
  log "Checking Azure VM SKUs from config"

  local sku
  while IFS= read -r sku; do
    [[ -n "${sku}" ]] || continue

    az vm list-skus \
      --location "${AZURE_LOCATION}" \
      --resource-type virtualMachines \
      --query "[?name=='${sku}'] | length(@)" \
      -o tsv | grep -qx '1' || fail "VM SKU ${sku} is not available in ${AZURE_LOCATION}"
  done < <(extract_azure_vm_sizes)
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
  log "Running Terraform init for Azure backend"
  terraform -chdir="${TERRAFORM_DIR}" init -reconfigure -backend-config="${BACKEND_FILE}" >/dev/null
}

print_summary() {
  cat <<EOF

Azure bootstrap: ok
  Subscription : ${AZURE_SUBSCRIPTION_ID}
  Tenant       : ${AZURE_TENANT_ID}
  Location     : ${AZURE_LOCATION}
  Resource group: ${AZURE_RESOURCE_GROUP_NAME}
  Key Vault    : ${AZURE_KEY_VAULT_NAME}
  Backend      : s3://${BACKEND_BUCKET}

Next step:
  source .env
  CLOUD_PROVIDER=azure ./deploy.sh all
EOF
}

main() {
  check_tools
  load_env
  load_config
  check_azure_login
  check_azure_subscription
  check_azure_providers
  check_resource_group
  check_key_vault
  check_key_vault_secrets
  check_ssh_key
  check_azure_vm_skus
  check_aws_backend_access
  terraform_init
  print_summary
}

main "$@"
