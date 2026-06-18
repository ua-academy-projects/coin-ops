#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PLATFORM_DIR="${REPO_ROOT}/azure-aks-jenkins"
TF_DIR="${PLATFORM_DIR}/terraform"
TF_SP_ENV="${PLATFORM_DIR}/.generated/terraform-sp.env"
LEGACY_TERRAFORM_DIR="${REPO_ROOT}/terraform.gcp.aws"
ROOT_ENV_FILE="${REPO_ROOT}/.env"

JOB_NAME="${JOB_NAME:-coin-ops-aks-cd}"
APP_DOMAIN="${APP_DOMAIN:-}"
DELETE_JENKINS_CREDENTIALS="${DELETE_JENKINS_CREDENTIALS:-true}"
DELETE_CLOUDFLARE_RECORD="${DELETE_CLOUDFLARE_RECORD:-true}"
AWS_REGION_FROM_CONFIG=""
GCP_PROJECT_ID_FROM_CONFIG=""
AZURE_KEY_VAULT_NAME_FROM_CONFIG=""

required_commands=(terraform kubectl az curl python3)

log() {
  printf '[destroy-jenkins] %s\n' "$*"
}

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

for cmd in "${required_commands[@]}"; do
  require_command "${cmd}"
done

if [[ ! -f "${TF_SP_ENV}" ]]; then
  echo "Missing Terraform service principal env file: ${TF_SP_ENV}" >&2
  exit 1
fi

if [[ -f "${ROOT_ENV_FILE}" ]]; then
  set -a
  . "${ROOT_ENV_FILE}"
  set +a
fi

if [[ -z "${APP_DOMAIN}" && -n "${TF_VAR_cloudflare_zone_name:-}" ]]; then
  APP_DOMAIN="${TF_VAR_cloudflare_zone_name}"
fi

if [[ -z "${APP_DOMAIN}" && -n "${CLOUDFLARE_ZONE_NAME:-}" ]]; then
  APP_DOMAIN="${CLOUDFLARE_ZONE_NAME}"
fi

source "${TF_SP_ENV}"

ensure_azure_sp_login() {
  if az account show >/dev/null 2>&1; then
    local current_subscription
    current_subscription="$(az account show --query id -o tsv 2>/dev/null || true)"
    if [[ "${current_subscription}" == "${ARM_SUBSCRIPTION_ID}" ]]; then
      return
    fi
  fi

  az login \
    --service-principal \
    --username "${ARM_CLIENT_ID}" \
    --password "${ARM_CLIENT_SECRET}" \
    --tenant "${ARM_TENANT_ID}" \
    >/dev/null
  az account set --subscription "${ARM_SUBSCRIPTION_ID}"
}

resolve_cloud_provider() {
  if [[ -n "${CLOUD_PROVIDER:-}" ]]; then
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
    ' "${LEGACY_TERRAFORM_DIR}/variables.tf"
  })"

  if [[ -z "${CLOUD_PROVIDER}" && -f "${LEGACY_TERRAFORM_DIR}/config.yml" ]]; then
    if awk '
      $1 == "azure:" { in_azure=1; next }
      in_azure && $1 == "key_vault_name:" { found=1; exit }
      in_azure && /^[^[:space:]]/ { exit }
      END { exit(found ? 0 : 1) }
    ' "${LEGACY_TERRAFORM_DIR}/config.yml"; then
      CLOUD_PROVIDER="azure"
    fi
  fi
}

resolve_aws_region() {
  AWS_REGION_FROM_CONFIG="$(
    awk '
      $1 == "aws:" { in_aws=1; next }
      in_aws && $1 == "region:" { gsub(/"/, "", $2); print $2; exit }
      in_aws && /^[^[:space:]]/ { exit }
    ' "${LEGACY_TERRAFORM_DIR}/config.yml"
  )"
}

resolve_gcp_project_id() {
  GCP_PROJECT_ID_FROM_CONFIG="$(
    awk '
      $1 == "gcp:" { in_gcp=1; next }
      in_gcp && $1 == "id:" { gsub(/"/, "", $2); print $2; exit }
      in_gcp && /^[^[:space:]]/ { exit }
    ' "${LEGACY_TERRAFORM_DIR}/config.yml"
  )"
}

resolve_azure_key_vault_name() {
  AZURE_KEY_VAULT_NAME_FROM_CONFIG="$(
    awk '
      $1 == "azure:" { in_azure=1; next }
      in_azure && $1 == "key_vault_name:" { gsub(/"/, "", $2); print $2; exit }
      in_azure && /^[^[:space:]]/ { exit }
    ' "${LEGACY_TERRAFORM_DIR}/config.yml"
  )"
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

read_azure_secret_with_fallback() {
  local secret_id="$1"
  local secret_value=""

  if secret_value="$(read_azure_secret "${secret_id}" 2>/dev/null)"; then
    printf '%s' "${secret_value}"
    return 0
  fi

  ensure_azure_sp_login
  read_azure_secret "${secret_id}"
}

resolve_cloudflare_token() {
  if [[ "${DELETE_CLOUDFLARE_RECORD}" != "true" || -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
    return
  fi

  resolve_cloud_provider
  case "${CLOUD_PROVIDER:-}" in
    aws)
      resolve_aws_region
      export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-$(read_aws_secret "${AWS_SECRET_CLOUDFLARE_TOKEN_ID:-coinops/cloudflare-api-token}")}"
      ;;
    gcp)
      resolve_gcp_project_id
      export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-$(read_gcp_secret "${GCP_SECRET_CLOUDFLARE_TOKEN_ID:-coinops-cloudflare-api-token}")}"
      ;;
    azure)
      resolve_azure_key_vault_name
      export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-$(read_azure_secret_with_fallback "${AZURE_SECRET_CLOUDFLARE_TOKEN_ID:-coinops-cloudflare-api-token}")}"
      ;;
    *)
      :
      ;;
  esac
}

resolve_cloudflare_zone_id() {
  if [[ "${DELETE_CLOUDFLARE_RECORD}" != "true" || -n "${CLOUDFLARE_ZONE_ID:-}" || -z "${CLOUDFLARE_API_TOKEN:-}" || -z "${APP_DOMAIN}" ]]; then
    return
  fi

  local response
  response="$(
    curl --silent --show-error --fail \
      -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
      "https://api.cloudflare.com/client/v4/zones?name=${APP_DOMAIN}"
  )"

  CLOUDFLARE_ZONE_ID="$(
    python3 -c 'import json,sys; data=json.load(sys.stdin); result=data.get("result", []); print(result[0]["id"] if result else "")' <<<"${response}"
  )"

  if [[ -n "${CLOUDFLARE_ZONE_ID:-}" ]]; then
    export CLOUDFLARE_ZONE_ID
  fi
}

tf_output() {
  terraform -chdir="${TF_DIR}" output -raw "$1" 2>/dev/null || true
}

RESOURCE_GROUP_NAME="$(tf_output resource_group_name)"
AKS_NAME="$(tf_output aks_name)"
JENKINS_NAMESPACE="$(tf_output jenkins_namespace)"
JENKINS_SERVICE_NAME="$(tf_output jenkins_service_name)"
JENKINS_ADMIN_USERNAME="$(tf_output jenkins_admin_username)"
JENKINS_ADMIN_PASSWORD="$(tf_output jenkins_admin_password)"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
KUBECONFIG_FILE="${TMP_DIR}/aks-kubeconfig"
JENKINS_COOKIE_JAR="${TMP_DIR}/jenkins.cookies"

resolve_cloudflare_token
resolve_cloudflare_zone_id

jenkins_credential_exists() {
  local cred_id="$1"
  curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    --user "${JENKINS_ADMIN_USERNAME}:${JENKINS_ADMIN_PASSWORD}" \
    "${JENKINS_URL}/credentials/store/system/domain/_/credential/${cred_id}/api/json" | grep -q '^200$'
}

job_exists() {
  curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    --user "${JENKINS_ADMIN_USERNAME}:${JENKINS_ADMIN_PASSWORD}" \
    "${JENKINS_URL}/job/${JOB_NAME}/api/json" | grep -q '^200$'
}

cleanup_cloudflare_record() {
  if [[ "${DELETE_CLOUDFLARE_RECORD}" != "true" ]]; then
    return
  fi

  if [[ -z "${APP_DOMAIN}" || -z "${CLOUDFLARE_API_TOKEN:-}" || -z "${CLOUDFLARE_ZONE_ID:-}" ]]; then
    log "Skipping Cloudflare record cleanup because APP_DOMAIN/token/zone ID is not available."
    return
  fi

  log "Deleting Cloudflare DNS record coin-ops.${APP_DOMAIN}."
  CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN}" \
  CLOUDFLARE_ZONE_ID="${CLOUDFLARE_ZONE_ID}" \
  "${SCRIPT_DIR}/cloudflare-dns.sh" delete "coin-ops.${APP_DOMAIN}" || true
}

cleanup_jenkins() {
  if [[ -z "${RESOURCE_GROUP_NAME}" || -z "${AKS_NAME}" || -z "${JENKINS_NAMESPACE}" || -z "${JENKINS_SERVICE_NAME}" || -z "${JENKINS_ADMIN_USERNAME}" || -z "${JENKINS_ADMIN_PASSWORD}" ]]; then
    log "Skipping Jenkins cleanup because Terraform outputs are incomplete."
    cleanup_cloudflare_record
    return
  fi

  ensure_azure_sp_login

  if ! az aks show --resource-group "${RESOURCE_GROUP_NAME}" --name "${AKS_NAME}" >/dev/null 2>&1; then
    log "Skipping Jenkins cleanup because AKS cluster ${AKS_NAME} no longer exists."
    cleanup_cloudflare_record
    return
  fi

  log "Fetching AKS kubeconfig for ${AKS_NAME}."
  az aks get-credentials \
    --resource-group "${RESOURCE_GROUP_NAME}" \
    --name "${AKS_NAME}" \
    --file "${KUBECONFIG_FILE}" \
    --overwrite-existing \
    >/dev/null

  local jenkins_host=""
  local jenkins_port=""
  for _ in $(seq 1 12); do
    jenkins_host="$(kubectl --kubeconfig "${KUBECONFIG_FILE}" get svc "${JENKINS_SERVICE_NAME}" -n "${JENKINS_NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    if [[ -z "${jenkins_host}" ]]; then
      jenkins_host="$(kubectl --kubeconfig "${KUBECONFIG_FILE}" get svc "${JENKINS_SERVICE_NAME}" -n "${JENKINS_NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
    fi
    jenkins_port="$(kubectl --kubeconfig "${KUBECONFIG_FILE}" get svc "${JENKINS_SERVICE_NAME}" -n "${JENKINS_NAMESPACE}" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || true)"
    if [[ -n "${jenkins_host}" && -n "${jenkins_port}" ]]; then
      break
    fi
    sleep 5
  done

  if [[ -z "${jenkins_host}" || -z "${jenkins_port}" ]]; then
    log "Skipping Jenkins cleanup because service endpoint could not be resolved."
    cleanup_cloudflare_record
    return
  fi

  if [[ "${jenkins_port}" == "80" ]]; then
    JENKINS_URL="http://${jenkins_host}"
  else
    JENKINS_URL="http://${jenkins_host}:${jenkins_port}"
  fi

  log "Jenkins URL: ${JENKINS_URL}"

  if ! curl --silent --show-error --fail "${JENKINS_URL}/login" >/dev/null 2>&1; then
    log "Skipping Jenkins cleanup because Jenkins is not reachable."
    cleanup_cloudflare_record
    return
  fi

  local crumb_json
  local crumb_field=""
  local crumb_value=""
  crumb_json="$(
    curl --silent --show-error --fail \
      --cookie-jar "${JENKINS_COOKIE_JAR}" \
      --cookie "${JENKINS_COOKIE_JAR}" \
      --user "${JENKINS_ADMIN_USERNAME}:${JENKINS_ADMIN_PASSWORD}" \
      "${JENKINS_URL}/crumbIssuer/api/json" 2>/dev/null || true
  )"

  if [[ -n "${crumb_json}" ]]; then
    crumb_field="$(python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("crumbRequestField",""))' <<<"${crumb_json}")"
    crumb_value="$(python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("crumb",""))' <<<"${crumb_json}")"
  fi

  curl_auth_args=(
    --silent
    --show-error
    --fail
    --cookie-jar "${JENKINS_COOKIE_JAR}"
    --cookie "${JENKINS_COOKIE_JAR}"
    --user "${JENKINS_ADMIN_USERNAME}:${JENKINS_ADMIN_PASSWORD}"
  )

  if [[ -n "${crumb_field}" && -n "${crumb_value}" ]]; then
    curl_auth_args+=(-H "${crumb_field}: ${crumb_value}")
  fi

  if job_exists; then
    log "Deleting Jenkins job ${JOB_NAME}."
    curl "${curl_auth_args[@]}" \
      -X POST \
      "${JENKINS_URL}/job/${JOB_NAME}/doDelete" \
      >/dev/null
  else
    log "Jenkins job ${JOB_NAME} is already absent."
  fi

  if [[ "${DELETE_JENKINS_CREDENTIALS}" == "true" ]]; then
    local credentials_to_delete=(
      AZURE_CLIENT_ID
      AZURE_CLIENT_SECRET
      AZURE_TENANT_ID
      AZURE_SUBSCRIPTION_ID
      ACR_NAME
      acr-push
      CLOUDFLARE_API_TOKEN
      CLOUDFLARE_ZONE_ID
      KUBECONFIG
    )

    for cred_id in "${credentials_to_delete[@]}"; do
      if jenkins_credential_exists "${cred_id}"; then
        log "Deleting Jenkins credential ${cred_id}."
        curl "${curl_auth_args[@]}" \
          -X POST \
          "${JENKINS_URL}/credentials/store/system/domain/_/credential/${cred_id}/doDelete" \
          >/dev/null
      fi
    done
  fi

  cleanup_cloudflare_record
  log "Jenkins cleanup completed."
}

cleanup_jenkins
