#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="${PROJECT_NAME:-azure-aks-jenkins}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
LOCATION="${AZURE_LOCATION:-westeurope}"
TF_DIR="${ROOT_DIR}/terraform"
ENV_DIR="${ROOT_DIR}/environments/${ENVIRONMENT}"
GENERATED_DIR="${ROOT_DIR}/.generated"
TFVARS_PATH="${ENV_DIR}/terraform.tfvars"
BACKEND_CONFIG_PATH="${GENERATED_DIR}/backend.hcl"
SP_ENV_PATH="${GENERATED_DIR}/terraform-sp.env"
TMP_KUBECONFIG_PATH="${GENERATED_DIR}/bootstrap-kubeconfig"
REPO_ROOT="$(cd "${ROOT_DIR}/.." && pwd)"
JENKINS_BOOTSTRAP_SCRIPT="${REPO_ROOT}/scripts/bootstrap-jenkins-job.sh"
LEGACY_CONFIG_PATH="${REPO_ROOT}/terraform.gcp.aws/config.yml"
CLUSTER_ISSUER_TEMPLATE_PATH="${ROOT_DIR}/k8s/cluster-issuer.yaml.tpl"

TARGET_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
BACKEND_RG_NAME="${TF_BACKEND_RESOURCE_GROUP:-${PROJECT_NAME}-${ENVIRONMENT}-tfstate-rg}"
BACKEND_CONTAINER_NAME="${TF_BACKEND_CONTAINER:-tfstate}"
TFSTATE_KEY="${TFSTATE_KEY:-${PROJECT_NAME}/${ENVIRONMENT}/terraform.tfstate}"
NAME_PREFIX="${NAME_PREFIX:-azplat}"
AKS_KUBERNETES_VERSION="${AKS_KUBERNETES_VERSION:-1.34.8}"
AKS_NODE_COUNT="${AKS_NODE_COUNT:-1}"
AKS_NODE_VM_SIZE="${AKS_NODE_VM_SIZE:-Standard_D2s_v4}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-$(git -C "${REPO_ROOT}" config user.email || true)}"
ALERT_EMAIL="${ALERT_EMAIL:-$(git -C "${REPO_ROOT}" config user.email || true)}"
JENKINS_ADMIN_USERNAME="${JENKINS_ADMIN_USERNAME:-admin}"
APP_NAMESPACE="${APP_NAMESPACE:-apps}"
JENKINS_NAMESPACE="${JENKINS_NAMESPACE:-jenkins}"
CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
CLUSTER_ISSUER_NAME="${CLUSTER_ISSUER_NAME:-letsencrypt-prod}"
INGRESS_CLASS_NAME="${INGRESS_CLASS_NAME:-traefik}"
TERRAFORM_SP_NAME="${TERRAFORM_SP_NAME:-${PROJECT_NAME}-${ENVIRONMENT}-terraform-sp}"
TF_AUTO_APPROVE="${TF_AUTO_APPROVE:-true}"
BOOTSTRAP_JENKINS_JOB="${BOOTSTRAP_JENKINS_JOB:-true}"
LEGACY_AZURE_KEY_VAULT_NAME=""
LEGACY_AZURE_RESOURCE_GROUP_NAME=""

required_commands=(az terraform kubectl helm docker git python3)

log() {
  printf '[bootstrap] %s\n' "$*"
}

fail() {
  printf '[bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
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

resolve_legacy_azure_key_vault_name() {
  if [[ ! -f "${LEGACY_CONFIG_PATH}" ]]; then
    return
  fi

  LEGACY_AZURE_KEY_VAULT_NAME="$(
    awk '
      $1 == "azure:" { in_azure=1; next }
      in_azure && $1 == "key_vault_name:" { gsub(/"/, "", $2); print $2; exit }
      in_azure && /^[^[:space:]]/ { exit }
    ' "${LEGACY_CONFIG_PATH}"
  )"

  LEGACY_AZURE_RESOURCE_GROUP_NAME="$(
    awk '
      $1 == "azure:" { in_azure=1; next }
      in_azure && $1 == "resource_group_name:" { gsub(/"/, "", $2); print $2; exit }
      in_azure && /^[^[:space:]]/ { exit }
    ' "${LEGACY_CONFIG_PATH}"
  )"
}

ensure_backend_resources() {
  log "Ensuring Terraform backend resource group '${BACKEND_RG_NAME}'."
  az group create --name "${BACKEND_RG_NAME}" --location "${LOCATION}" >/dev/null

  if ! az storage account show --name "${TF_BACKEND_STORAGE_ACCOUNT}" --resource-group "${BACKEND_RG_NAME}" >/dev/null 2>&1; then
    log "Creating Terraform backend storage account '${TF_BACKEND_STORAGE_ACCOUNT}'."
    az storage account create \
      --name "${TF_BACKEND_STORAGE_ACCOUNT}" \
      --resource-group "${BACKEND_RG_NAME}" \
      --location "${LOCATION}" \
      --sku Standard_LRS \
      --kind StorageV2 \
      --min-tls-version TLS1_2 \
      --allow-blob-public-access false >/dev/null
  else
    log "Reusing Terraform backend storage account '${TF_BACKEND_STORAGE_ACCOUNT}'."
  fi

  log "Ensuring Terraform backend blob container '${BACKEND_CONTAINER_NAME}'."
  az storage container create \
    --name "${BACKEND_CONTAINER_NAME}" \
    --account-name "${TF_BACKEND_STORAGE_ACCOUNT}" \
    --auth-mode login >/dev/null
}

get_sp_app_id() {
  az ad sp list --display-name "${TERRAFORM_SP_NAME}" --query "[0].appId" -o tsv
}

write_sp_env_file() {
  mkdir -p "${GENERATED_DIR}"
  cat >"${SP_ENV_PATH}" <<EOF
export ARM_CLIENT_ID="${ARM_CLIENT_ID}"
export ARM_CLIENT_SECRET="${ARM_CLIENT_SECRET}"
export ARM_SUBSCRIPTION_ID="${TARGET_SUBSCRIPTION_ID}"
export ARM_TENANT_ID="${AZURE_TENANT_ID}"
export ARM_USE_AZUREAD=true
EOF
  chmod 600 "${SP_ENV_PATH}"
}

ensure_terraform_service_principal() {
  local app_id
  local sp_json

  if [[ -f "${SP_ENV_PATH}" ]]; then
    # shellcheck disable=SC1090
    . "${SP_ENV_PATH}"
    if [[ -n "${ARM_CLIENT_ID:-}" && -n "${ARM_CLIENT_SECRET:-}" ]]; then
      return
    fi
  fi

  app_id="$(get_sp_app_id)"

  if [[ -z "${app_id}" ]]; then
    log "Creating Terraform service principal '${TERRAFORM_SP_NAME}'."
    sp_json="$(az ad sp create-for-rbac --name "${TERRAFORM_SP_NAME}" --skip-assignment -o json)"
    ARM_CLIENT_ID="$(printf '%s' "${sp_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["appId"])')"
    ARM_CLIENT_SECRET="$(printf '%s' "${sp_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')"
  else
    log "Reusing Terraform service principal '${TERRAFORM_SP_NAME}' and resetting credentials locally."
    sp_json="$(az ad sp credential reset --id "${app_id}" --append -o json)"
    ARM_CLIENT_ID="${app_id}"
    ARM_CLIENT_SECRET="$(printf '%s' "${sp_json}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')"
  fi

  export ARM_CLIENT_ID ARM_CLIENT_SECRET
  write_sp_env_file
}

ensure_role_assignment() {
  local assignee="$1"
  local role="$2"
  local scope="$3"

  if az role assignment list \
    --assignee "${assignee}" \
    --role "${role}" \
    --scope "${scope}" \
    --query "[0].id" -o tsv | grep -q .; then
    return
  fi

  log "Assigning role '${role}' on '${scope}'."
  az role assignment create --assignee "${assignee}" --role "${role}" --scope "${scope}" >/dev/null
}

ensure_terraform_rbac() {
  local backend_rg_scope="/subscriptions/${TARGET_SUBSCRIPTION_ID}/resourceGroups/${BACKEND_RG_NAME}"
  local subscription_scope="/subscriptions/${TARGET_SUBSCRIPTION_ID}"

  ensure_role_assignment "${ARM_CLIENT_ID}" "Contributor" "${backend_rg_scope}"
  ensure_role_assignment "${ARM_CLIENT_ID}" "Storage Blob Data Contributor" "${backend_rg_scope}"
  ensure_role_assignment "${ARM_CLIENT_ID}" "Contributor" "${subscription_scope}"
  ensure_role_assignment "${ARM_CLIENT_ID}" "User Access Administrator" "${subscription_scope}"

  if [[ -n "${LEGACY_AZURE_KEY_VAULT_NAME}" && -n "${LEGACY_AZURE_RESOURCE_GROUP_NAME}" ]]; then
    local key_vault_scope="/subscriptions/${TARGET_SUBSCRIPTION_ID}/resourceGroups/${LEGACY_AZURE_RESOURCE_GROUP_NAME}/providers/Microsoft.KeyVault/vaults/${LEGACY_AZURE_KEY_VAULT_NAME}"
    ensure_role_assignment "${ARM_CLIENT_ID}" "Key Vault Secrets User" "${key_vault_scope}"
  fi
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
    log "Reusing existing tfvars '${TFVARS_PATH}'."
    return
  fi

  log "Generating '${TFVARS_PATH}'."
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
  export ARM_SUBSCRIPTION_ID="${TARGET_SUBSCRIPTION_ID}"
  export ARM_TENANT_ID="${AZURE_TENANT_ID}"
  export ARM_USE_AZUREAD=true
  export TF_VAR_letsencrypt_email="${LETSENCRYPT_EMAIL}"
  export TF_VAR_alert_email="${ALERT_EMAIL}"
}

apply_cluster_issuer() {
  if [[ -z "${LETSENCRYPT_EMAIL}" ]]; then
    fail "LETSENCRYPT_EMAIL is empty; cannot configure ClusterIssuer."
  fi

  if [[ ! -f "${CLUSTER_ISSUER_TEMPLATE_PATH}" ]]; then
    fail "Missing ClusterIssuer template: ${CLUSTER_ISSUER_TEMPLATE_PATH}"
  fi

  mkdir -p "${GENERATED_DIR}"

  log "Fetching AKS kubeconfig for ClusterIssuer bootstrap."
  az aks get-credentials \
    --resource-group "${TF_RESOURCE_GROUP_NAME}" \
    --name "${TF_AKS_NAME}" \
    --file "${TMP_KUBECONFIG_PATH}" \
    --overwrite-existing \
    >/dev/null

  log "Waiting for cert-manager deployments."
  kubectl --kubeconfig "${TMP_KUBECONFIG_PATH}" rollout status deployment/cert-manager -n "${CERT_MANAGER_NAMESPACE}" --timeout=300s
  kubectl --kubeconfig "${TMP_KUBECONFIG_PATH}" rollout status deployment/cert-manager-cainjector -n "${CERT_MANAGER_NAMESPACE}" --timeout=300s
  kubectl --kubeconfig "${TMP_KUBECONFIG_PATH}" rollout status deployment/cert-manager-webhook -n "${CERT_MANAGER_NAMESPACE}" --timeout=300s

  log "Applying ClusterIssuer ${CLUSTER_ISSUER_NAME}."
  python3 - "${CLUSTER_ISSUER_TEMPLATE_PATH}" "${CLUSTER_ISSUER_NAME}" "${LETSENCRYPT_EMAIL}" "${INGRESS_CLASS_NAME}" <<'PY' \
    | kubectl --kubeconfig "${TMP_KUBECONFIG_PATH}" apply -f -
from pathlib import Path
import sys

template_path, issuer_name, email, ingress_class = sys.argv[1:5]
content = Path(template_path).read_text()
content = content.replace("${CLUSTER_ISSUER_NAME}", issuer_name)
content = content.replace("${LETSENCRYPT_EMAIL}", email)
content = content.replace("${INGRESS_CLASS_NAME}", ingress_class)
sys.stdout.write(content)
PY
}

run_terraform() {
  log "Running terraform init."
  terraform -chdir="${TF_DIR}" init -reconfigure -backend-config="${BACKEND_CONFIG_PATH}"

  local apply_args=()
  if [[ "${TF_AUTO_APPROVE}" == "true" ]]; then
    apply_args+=("-auto-approve")
  fi

  log "Running terraform apply."
  terraform -chdir="${TF_DIR}" apply \
    -var-file="${TFVARS_PATH}" \
    "${apply_args[@]}"
}

run_jenkins_job_bootstrap() {
  if [[ "${BOOTSTRAP_JENKINS_JOB}" != "true" ]]; then
    log "Skipping Jenkins job bootstrap because BOOTSTRAP_JENKINS_JOB=${BOOTSTRAP_JENKINS_JOB}."
    return
  fi

  if [[ ! -x "${JENKINS_BOOTSTRAP_SCRIPT}" ]]; then
    if [[ -f "${JENKINS_BOOTSTRAP_SCRIPT}" ]]; then
      chmod +x "${JENKINS_BOOTSTRAP_SCRIPT}"
    else
      fail "Missing Jenkins bootstrap script: ${JENKINS_BOOTSTRAP_SCRIPT}"
    fi
  fi

  log "Bootstrapping Jenkins credentials and Pipeline job."
  "${JENKINS_BOOTSTRAP_SCRIPT}"
}

main() {
  require_commands
  ensure_azure_login
  select_subscription
  load_subscription_context
  resolve_legacy_azure_key_vault_name
  ensure_backend_resources
  ensure_terraform_service_principal
  export_arm_env
  ensure_terraform_rbac
  write_backend_config
  generate_tfvars_if_missing
  run_terraform
  apply_cluster_issuer
  run_jenkins_job_bootstrap

  log "Bootstrap completed."
  log "Service principal environment file: ${SP_ENV_PATH}"
  log "Terraform variable file: ${TFVARS_PATH}"
}

main "$@"
