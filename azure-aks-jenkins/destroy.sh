#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="${PROJECT_NAME:-azure-aks-jenkins}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
TF_DIR="${ROOT_DIR}/terraform"
ENV_DIR="${ROOT_DIR}/environments/${ENVIRONMENT}"
GENERATED_DIR="${ROOT_DIR}/.generated"
TFVARS_PATH="${ENV_DIR}/terraform.tfvars"
BACKEND_CONFIG_PATH="${GENERATED_DIR}/backend.hcl"
SP_ENV_PATH="${GENERATED_DIR}/terraform-sp.env"
REPO_ROOT="$(cd "${ROOT_DIR}/.." && pwd)"
JENKINS_DESTROY_SCRIPT="${REPO_ROOT}/scripts/destroy-jenkins-job.sh"
LEGACY_CONFIG_PATH="${REPO_ROOT}/terraform.gcp.aws/config.yml"
MONITORING_WORKBOOK_DELETE_SCRIPT="${ROOT_DIR}/scripts/delete-monitoring-workbook.sh"

CONFIG_AZURE_SUBSCRIPTION_ID=""
CONFIG_AZURE_LOCATION=""
CONFIG_AZURE_MONITORING_ALERT_EMAIL=""
CONFIG_AZURE_MONITORING_LOG_RETENTION_DAYS=""
CONFIG_AZURE_MONITORING_CPU_ALERT_THRESHOLD=""
CONFIG_AZURE_MONITORING_CPU_ALERT_SEVERITY=""
CONFIG_AZURE_MONITORING_HEARTBEAT_ALERT_SEVERITY=""
CONFIG_AZURE_MONITORING_HEARTBEAT_WINDOW_MINUTES=""
CONFIG_AZURE_MONITORING_HEARTBEAT_EVALUATION_FREQUENCY=""

LOCATION="${AZURE_LOCATION:-}"
TARGET_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
BACKEND_RG_NAME="${TF_BACKEND_RESOURCE_GROUP:-${PROJECT_NAME}-${ENVIRONMENT}-tfstate-rg}"
BACKEND_CONTAINER_NAME="${TF_BACKEND_CONTAINER:-tfstate}"
TFSTATE_KEY="${TFSTATE_KEY:-${PROJECT_NAME}/${ENVIRONMENT}/terraform.tfstate}"
NAME_PREFIX="${NAME_PREFIX:-azplat}"
AKS_KUBERNETES_VERSION="${AKS_KUBERNETES_VERSION:-1.34.8}"
AKS_NODE_COUNT="${AKS_NODE_COUNT:-2}"
AKS_NODE_VM_SIZE="${AKS_NODE_VM_SIZE:-Standard_D2s_v4}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-$(git -C "${REPO_ROOT}" config user.email || true)}"
ALERT_EMAIL="${ALERT_EMAIL:-}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-}"
CPU_ALERT_THRESHOLD="${CPU_ALERT_THRESHOLD:-}"
CPU_ALERT_SEVERITY="${CPU_ALERT_SEVERITY:-}"
HEARTBEAT_ALERT_SEVERITY="${HEARTBEAT_ALERT_SEVERITY:-}"
HEARTBEAT_WINDOW_MINUTES="${HEARTBEAT_WINDOW_MINUTES:-}"
HEARTBEAT_EVALUATION_FREQUENCY="${HEARTBEAT_EVALUATION_FREQUENCY:-}"
JENKINS_ADMIN_USERNAME="${JENKINS_ADMIN_USERNAME:-admin}"
APP_NAMESPACE="${APP_NAMESPACE:-apps}"
JENKINS_NAMESPACE="${JENKINS_NAMESPACE:-jenkins}"
TERRAFORM_SP_NAME="${TERRAFORM_SP_NAME:-${PROJECT_NAME}-${ENVIRONMENT}-terraform-sp}"
TF_AUTO_APPROVE="${TF_AUTO_APPROVE:-true}"
CLEANUP_JENKINS_JOB="${CLEANUP_JENKINS_JOB:-true}"
DESTROY_BACKEND="${DESTROY_BACKEND:-false}"
DELETE_TERRAFORM_SP="${DELETE_TERRAFORM_SP:-false}"

required_commands=(az terraform python3 git)

terraform_destroy_targets=(
  "module.jenkins"
  "module.cert_manager"
  "module.traefik"
)

log() {
  printf '[destroy] %s\n' "$*"
}

fail() {
  printf '[destroy] ERROR: %s\n' "$*" >&2
  exit 1
}

extract_config_value() {
  local scope="$1"
  local section="$2"
  local key="$3"

  awk -v scope="${scope}" -v section="${section}" -v key="${key}" '
    $1 == scope ":" { in_scope=1; next }
    in_scope && $1 == section ":" { in_section=1; next }
    in_scope && in_section && $1 == key ":" {
      value=$0
      sub(/^[^:]+:[[:space:]]*/, "", value)
      gsub(/"/, "", value)
      print value
      exit
    }
    in_scope && in_section && /^[^[:space:]]/ { exit }
    in_scope && !in_section && /^[^[:space:]]/ && $1 != section ":" { exit }
  ' "${LEGACY_CONFIG_PATH}"
}

extract_nested_config_value() {
  local scope="$1"
  local section="$2"
  local subsection="$3"
  local key="$4"

  awk -v scope="${scope}" -v section="${section}" -v subsection="${subsection}" -v key="${key}" '
    $1 == scope ":" { in_scope=1; next }
    in_scope && $1 == section ":" { in_section=1; next }
    in_scope && in_section && $1 == subsection ":" { in_subsection=1; next }
    in_scope && in_section && in_subsection && $1 == key ":" {
      value=$0
      sub(/^[^:]+:[[:space:]]*/, "", value)
      gsub(/"/, "", value)
      print value
      exit
    }
    in_scope && in_section && in_subsection && /^[^[:space:]]/ { exit }
    in_scope && in_section && !in_subsection && /^[^[:space:]]/ && $1 != subsection ":" { exit }
    in_scope && !in_section && /^[^[:space:]]/ && $1 != section ":" { exit }
  ' "${LEGACY_CONFIG_PATH}"
}

require_commands() {
  local missing=()
  for cmd in "${required_commands[@]}"; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
      missing+=("${cmd}")
    fi
  done

  if ((${#missing[@]} > 0)); then
    fail "Missing prerequisites: ${missing[*]}"
  fi
}

load_legacy_config() {
  if [[ ! -f "${LEGACY_CONFIG_PATH}" ]]; then
    return
  fi

  CONFIG_AZURE_SUBSCRIPTION_ID="$(extract_config_value "project" "azure" "subscription_id")"
  CONFIG_AZURE_LOCATION="$(extract_config_value "project" "azure" "location")"
  CONFIG_AZURE_MONITORING_ALERT_EMAIL="$(extract_nested_config_value "project" "azure" "monitoring" "alert_email")"
  CONFIG_AZURE_MONITORING_LOG_RETENTION_DAYS="$(extract_nested_config_value "project" "azure" "monitoring" "log_retention_days")"
  CONFIG_AZURE_MONITORING_CPU_ALERT_THRESHOLD="$(extract_nested_config_value "project" "azure" "monitoring" "cpu_alert_threshold")"
  CONFIG_AZURE_MONITORING_CPU_ALERT_SEVERITY="$(extract_nested_config_value "project" "azure" "monitoring" "cpu_alert_severity")"
  CONFIG_AZURE_MONITORING_HEARTBEAT_ALERT_SEVERITY="$(extract_nested_config_value "project" "azure" "monitoring" "heartbeat_alert_severity")"
  CONFIG_AZURE_MONITORING_HEARTBEAT_WINDOW_MINUTES="$(extract_nested_config_value "project" "azure" "monitoring" "heartbeat_window_minutes")"
  CONFIG_AZURE_MONITORING_HEARTBEAT_EVALUATION_FREQUENCY="$(extract_nested_config_value "project" "azure" "monitoring" "heartbeat_evaluation_frequency")"

  TARGET_SUBSCRIPTION_ID="${TARGET_SUBSCRIPTION_ID:-${CONFIG_AZURE_SUBSCRIPTION_ID}}"
  LOCATION="${LOCATION:-${CONFIG_AZURE_LOCATION}}"
  ALERT_EMAIL="${CONFIG_AZURE_MONITORING_ALERT_EMAIL:-${ALERT_EMAIL:-}}"
  LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-${CONFIG_AZURE_MONITORING_LOG_RETENTION_DAYS}}"
  CPU_ALERT_THRESHOLD="${CPU_ALERT_THRESHOLD:-${CONFIG_AZURE_MONITORING_CPU_ALERT_THRESHOLD}}"
  CPU_ALERT_SEVERITY="${CPU_ALERT_SEVERITY:-${CONFIG_AZURE_MONITORING_CPU_ALERT_SEVERITY}}"
  HEARTBEAT_ALERT_SEVERITY="${HEARTBEAT_ALERT_SEVERITY:-${CONFIG_AZURE_MONITORING_HEARTBEAT_ALERT_SEVERITY}}"
  HEARTBEAT_WINDOW_MINUTES="${HEARTBEAT_WINDOW_MINUTES:-${CONFIG_AZURE_MONITORING_HEARTBEAT_WINDOW_MINUTES}}"
  HEARTBEAT_EVALUATION_FREQUENCY="${HEARTBEAT_EVALUATION_FREQUENCY:-${CONFIG_AZURE_MONITORING_HEARTBEAT_EVALUATION_FREQUENCY}}"
}

ensure_azure_login() {
  if az account show >/dev/null 2>&1; then
    return
  fi

  log "Azure CLI is not logged in. Starting 'az login'."
  az login >/dev/null
}

select_subscription() {
  if [[ -z "${TARGET_SUBSCRIPTION_ID}" ]]; then
    TARGET_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
  fi

  az account set --subscription "${TARGET_SUBSCRIPTION_ID}"
}

sanitize_storage_account_name() {
  local seed="${1,,}"
  seed="${seed//[^a-z0-9]/}"
  printf '%s' "${seed:0:20}"
}

load_subscription_context() {
  TARGET_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
  AZURE_TENANT_ID="$(az account show --query tenantId -o tsv)"
  SUBSCRIPTION_SUFFIX="$(printf '%s' "${TARGET_SUBSCRIPTION_ID}" | tr -d '-' | tail -c 7)"
  TF_BACKEND_STORAGE_ACCOUNT="${TF_BACKEND_STORAGE_ACCOUNT:-$(sanitize_storage_account_name "${NAME_PREFIX}${ENVIRONMENT}${SUBSCRIPTION_SUFFIX}tf")}"
  TF_RESOURCE_GROUP_NAME="${TF_RESOURCE_GROUP_NAME:-${NAME_PREFIX}-${ENVIRONMENT}-rg}"
  TF_AKS_NAME="${TF_AKS_NAME:-${NAME_PREFIX}-${ENVIRONMENT}-aks}"
  TF_ACR_NAME="${TF_ACR_NAME:-$(sanitize_storage_account_name "${NAME_PREFIX}${ENVIRONMENT}${SUBSCRIPTION_SUFFIX}acr")}"
  TF_DNS_PREFIX="${TF_DNS_PREFIX:-${NAME_PREFIX}-${ENVIRONMENT}-aks}"
}

write_backend_config() {
  mkdir -p "${GENERATED_DIR}"
  cat >"${BACKEND_CONFIG_PATH}" <<EOF
resource_group_name  = "${BACKEND_RG_NAME}"
storage_account_name = "${TF_BACKEND_STORAGE_ACCOUNT}"
container_name       = "${BACKEND_CONTAINER_NAME}"
key                  = "${TFSTATE_KEY}"
use_azuread_auth     = true
EOF
}

generate_tfvars_if_missing() {
  mkdir -p "${ENV_DIR}"
  if [[ -f "${TFVARS_PATH}" ]]; then
    return
  fi

  log "Generating '${TFVARS_PATH}' for destroy because it does not exist."
  cat >"${TFVARS_PATH}" <<EOF
environment            = "${ENVIRONMENT}"
location               = "${LOCATION}"
project_name           = "${PROJECT_NAME}"
name_prefix            = "${NAME_PREFIX}"
resource_group_name    = "${TF_RESOURCE_GROUP_NAME}"
aks_name               = "${TF_AKS_NAME}"
acr_name               = "${TF_ACR_NAME}"
dns_prefix             = "${TF_DNS_PREFIX}"
kubernetes_version     = "${AKS_KUBERNETES_VERSION}"
node_count             = ${AKS_NODE_COUNT}
node_vm_size           = "${AKS_NODE_VM_SIZE}"
jenkins_namespace      = "${JENKINS_NAMESPACE}"
app_namespace          = "${APP_NAMESPACE}"
jenkins_admin_username = "${JENKINS_ADMIN_USERNAME}"
tags = {
  environment = "${ENVIRONMENT}"
  managed-by  = "terraform"
  project     = "${PROJECT_NAME}"
}
EOF
}

export_arm_env() {
  if [[ ! -f "${SP_ENV_PATH}" ]]; then
    fail "Missing Terraform service principal environment file: ${SP_ENV_PATH}"
  fi

  # shellcheck disable=SC1090
  . "${SP_ENV_PATH}"
  export ARM_CLIENT_ID ARM_CLIENT_SECRET ARM_SUBSCRIPTION_ID ARM_TENANT_ID ARM_USE_AZUREAD
}

run_jenkins_cleanup() {
  if [[ "${CLEANUP_JENKINS_JOB}" != "true" ]]; then
    log "Skipping Jenkins cleanup because CLEANUP_JENKINS_JOB=${CLEANUP_JENKINS_JOB}."
    return
  fi

  if [[ ! -x "${JENKINS_DESTROY_SCRIPT}" ]]; then
    if [[ -f "${JENKINS_DESTROY_SCRIPT}" ]]; then
      chmod +x "${JENKINS_DESTROY_SCRIPT}"
    else
      fail "Missing Jenkins destroy script: ${JENKINS_DESTROY_SCRIPT}"
    fi
  fi

  log "Cleaning up Jenkins job, Jenkins credentials, and Cloudflare DNS record."
  "${JENKINS_DESTROY_SCRIPT}"
}

run_monitoring_workbook_cleanup() {
  if [[ ! -x "${MONITORING_WORKBOOK_DELETE_SCRIPT}" ]]; then
    if [[ -f "${MONITORING_WORKBOOK_DELETE_SCRIPT}" ]]; then
      chmod +x "${MONITORING_WORKBOOK_DELETE_SCRIPT}"
    else
      fail "Missing monitoring workbook cleanup script: ${MONITORING_WORKBOOK_DELETE_SCRIPT}"
    fi
  fi

  log "Cleaning up monitoring workbook."
  "${MONITORING_WORKBOOK_DELETE_SCRIPT}" \
    "${TF_RESOURCE_GROUP_NAME}" \
    "${PROJECT_NAME}" \
    "${ENVIRONMENT}"
}

terraform_destroy() {
  local destroy_args=("$@")

  terraform -chdir="${TF_DIR}" destroy \
    -var-file="${TFVARS_PATH}" \
    "${destroy_args[@]}"
}

run_terraform_destroy() {
  log "Running terraform init."
  terraform -chdir="${TF_DIR}" init -reconfigure -backend-config="${BACKEND_CONFIG_PATH}"

  local destroy_args=()
  if [[ "${TF_AUTO_APPROVE}" == "true" ]]; then
    destroy_args+=("-auto-approve")
  fi

  log "Running targeted terraform destroy for in-cluster resources."
  local targeted_destroy_args=("${destroy_args[@]}")
  local target
  for target in "${terraform_destroy_targets[@]}"; do
    targeted_destroy_args+=("-target=${target}")
  done
  terraform_destroy "${targeted_destroy_args[@]}"

  log "Running full terraform destroy."
  terraform_destroy "${destroy_args[@]}"
}

destroy_backend_resources() {
  if [[ "${DESTROY_BACKEND}" != "true" ]]; then
    log "Skipping backend resource deletion because DESTROY_BACKEND=${DESTROY_BACKEND}."
    return
  fi

  log "Deleting Terraform backend resource group ${BACKEND_RG_NAME}."
  az group delete --name "${BACKEND_RG_NAME}" --yes --no-wait
}

delete_terraform_service_principal() {
  if [[ "${DELETE_TERRAFORM_SP}" != "true" ]]; then
    log "Skipping Terraform service principal deletion because DELETE_TERRAFORM_SP=${DELETE_TERRAFORM_SP}."
    return
  fi

  if [[ -n "${ARM_CLIENT_ID:-}" ]]; then
    log "Deleting Terraform service principal ${ARM_CLIENT_ID}."
    az ad sp delete --id "${ARM_CLIENT_ID}" >/dev/null || true
  fi
}

main() {
  require_commands
  load_legacy_config
  ensure_azure_login
  select_subscription
  load_subscription_context
  export TF_VAR_letsencrypt_email="${LETSENCRYPT_EMAIL}"
  export TF_VAR_alert_email="${ALERT_EMAIL}"
  if [[ -n "${LOG_RETENTION_DAYS}" ]]; then export TF_VAR_log_retention_days="${LOG_RETENTION_DAYS}"; fi
  if [[ -n "${CPU_ALERT_THRESHOLD}" ]]; then export TF_VAR_cpu_alert_threshold="${CPU_ALERT_THRESHOLD}"; fi
  if [[ -n "${CPU_ALERT_SEVERITY}" ]]; then export TF_VAR_cpu_alert_severity="${CPU_ALERT_SEVERITY}"; fi
  if [[ -n "${HEARTBEAT_ALERT_SEVERITY}" ]]; then export TF_VAR_heartbeat_alert_severity="${HEARTBEAT_ALERT_SEVERITY}"; fi
  if [[ -n "${HEARTBEAT_WINDOW_MINUTES}" ]]; then export TF_VAR_heartbeat_window_minutes="${HEARTBEAT_WINDOW_MINUTES}"; fi
  if [[ -n "${HEARTBEAT_EVALUATION_FREQUENCY}" ]]; then export TF_VAR_heartbeat_evaluation_frequency="${HEARTBEAT_EVALUATION_FREQUENCY}"; fi
  export_arm_env
  write_backend_config
  generate_tfvars_if_missing
  run_jenkins_cleanup
  run_monitoring_workbook_cleanup
  run_terraform_destroy
  destroy_backend_resources
  delete_terraform_service_principal

  log "Destroy completed."
  log "Backend config: ${BACKEND_CONFIG_PATH}"
  log "Terraform variable file: ${TFVARS_PATH}"
}

main "$@"
