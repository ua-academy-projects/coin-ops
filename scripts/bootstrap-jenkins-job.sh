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
JENKINS_GIT_CREDENTIALS_ID="${JENKINS_GIT_CREDENTIALS_ID:-}"
TRIGGER_INITIAL_BUILD="${TRIGGER_INITIAL_BUILD:-true}"
WAIT_FOR_INITIAL_BUILD="${WAIT_FOR_INITIAL_BUILD:-true}"
INITIAL_BUILD_TIMEOUT_SECONDS="${INITIAL_BUILD_TIMEOUT_SECONDS:-1800}"
AWS_REGION_FROM_CONFIG=""
GCP_PROJECT_ID_FROM_CONFIG=""
AZURE_KEY_VAULT_NAME_FROM_CONFIG=""

required_commands=(terraform kubectl az curl python3 git base64)

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

if [[ -z "${APP_DOMAIN}" ]]; then
  echo "APP_DOMAIN is not set and could not be derived from .env (TF_VAR_cloudflare_zone_name)." >&2
  exit 1
fi

source "${TF_SP_ENV}"

export AZURE_CLIENT_ID="${ARM_CLIENT_ID}"
export AZURE_CLIENT_SECRET="${ARM_CLIENT_SECRET}"
export AZURE_SUBSCRIPTION_ID="${ARM_SUBSCRIPTION_ID}"
export AZURE_TENANT_ID="${ARM_TENANT_ID}"

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
    ' "${LEGACY_TERRAFORM_DIR}/config.yml"
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
    ' "${LEGACY_TERRAFORM_DIR}/config.yml"
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
    ' "${LEGACY_TERRAFORM_DIR}/config.yml"
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

load_aws_secrets() {
  resolve_aws_region
  export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-$(read_aws_secret "${AWS_SECRET_CLOUDFLARE_TOKEN_ID:-coinops/cloudflare-api-token}")}"
}

load_gcp_secrets() {
  resolve_gcp_project_id
  export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-$(read_gcp_secret "${GCP_SECRET_CLOUDFLARE_TOKEN_ID:-coinops-cloudflare-api-token}")}"
}

load_azure_secrets() {
  resolve_azure_key_vault_name
  export CLOUDFLARE_API_TOKEN="${CLOUDFLARE_API_TOKEN:-$(read_azure_secret_with_fallback "${AZURE_SECRET_CLOUDFLARE_TOKEN_ID:-coinops-cloudflare-api-token}")}"
}

resolve_cloudflare_token() {
  if [[ -n "${CLOUDFLARE_API_TOKEN:-}" ]]; then
    return
  fi

  resolve_cloud_provider
  case "${CLOUD_PROVIDER:-}" in
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
      :
      ;;
  esac
}

resolve_cloudflare_zone_id() {
  if [[ -n "${CLOUDFLARE_ZONE_ID:-}" ]]; then
    return
  fi

  if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
    return
  fi

  if [[ -z "${TF_VAR_cloudflare_zone_name:-}" ]]; then
    return
  fi

  local response
  response="$(
    curl --silent --show-error --fail \
      -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN:-}" \
      "https://api.cloudflare.com/client/v4/zones?name=${TF_VAR_cloudflare_zone_name}"
  )"

  CLOUDFLARE_ZONE_ID="$(
    python3 -c 'import json,sys; data=json.load(sys.stdin); result=data.get("result", []); print(result[0]["id"] if result else "")' <<<"${response}"
  )"

  if [[ -n "${CLOUDFLARE_ZONE_ID:-}" ]]; then
    export CLOUDFLARE_ZONE_ID
  fi
}

resolve_cloudflare_token
resolve_cloudflare_zone_id

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" || -z "${CLOUDFLARE_ZONE_ID:-}" ]]; then
  echo "Unable to resolve CLOUDFLARE_API_TOKEN and CLOUDFLARE_ZONE_ID from .env / secret manager flow." >&2
  exit 1
fi

tf_output() {
  terraform -chdir="${TF_DIR}" output -raw "$1"
}

RESOURCE_GROUP_NAME="$(tf_output resource_group_name)"
AKS_NAME="$(tf_output aks_name)"
ACR_NAME="$(tf_output acr_name)"
JENKINS_NAMESPACE="$(tf_output jenkins_namespace)"
JENKINS_SERVICE_NAME="$(tf_output jenkins_service_name)"
JENKINS_ADMIN_USERNAME="$(tf_output jenkins_admin_username)"
JENKINS_ADMIN_PASSWORD="$(tf_output jenkins_admin_password)"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT
KUBECONFIG_FILE="${TMP_DIR}/aks-kubeconfig"
JENKINS_COOKIE_JAR="${TMP_DIR}/jenkins.cookies"

echo "[bootstrap-jenkins] Logging into Azure with the Terraform service principal."
ensure_azure_sp_login

echo "[bootstrap-jenkins] Fetching AKS kubeconfig for ${AKS_NAME}."
az aks get-credentials \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --name "${AKS_NAME}" \
  --file "${KUBECONFIG_FILE}" \
  --overwrite-existing \
  >/dev/null

echo "[bootstrap-jenkins] Resolving Jenkins LoadBalancer endpoint."
JENKINS_PORT=""
JENKINS_HOST=""
for _ in $(seq 1 60); do
  JENKINS_HOST="$(kubectl --kubeconfig "${KUBECONFIG_FILE}" get svc "${JENKINS_SERVICE_NAME}" -n "${JENKINS_NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [[ -z "${JENKINS_HOST}" ]]; then
    JENKINS_HOST="$(kubectl --kubeconfig "${KUBECONFIG_FILE}" get svc "${JENKINS_SERVICE_NAME}" -n "${JENKINS_NAMESPACE}" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  fi
  JENKINS_PORT="$(kubectl --kubeconfig "${KUBECONFIG_FILE}" get svc "${JENKINS_SERVICE_NAME}" -n "${JENKINS_NAMESPACE}" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || true)"
  if [[ -n "${JENKINS_HOST}" && -n "${JENKINS_PORT}" ]]; then
    break
  fi
  sleep 10
done

if [[ -z "${JENKINS_HOST}" || -z "${JENKINS_PORT}" ]]; then
  echo "Failed to resolve Jenkins service endpoint from Kubernetes." >&2
  exit 1
fi

if [[ "${JENKINS_PORT}" == "80" ]]; then
  JENKINS_URL="http://${JENKINS_HOST}"
else
  JENKINS_URL="http://${JENKINS_HOST}:${JENKINS_PORT}"
fi

echo "[bootstrap-jenkins] Jenkins URL: ${JENKINS_URL}"

echo "[bootstrap-jenkins] Waiting for Jenkins HTTP endpoint."
for _ in $(seq 1 60); do
  if curl --silent --show-error --fail "${JENKINS_URL}/login" >/dev/null 2>&1; then
    break
  fi
  sleep 10
done

if ! curl --silent --show-error --fail "${JENKINS_URL}/login" >/dev/null 2>&1; then
  echo "Jenkins is not reachable at ${JENKINS_URL}" >&2
  exit 1
fi

get_crumb() {
  curl --silent --show-error --fail \
    --cookie-jar "${JENKINS_COOKIE_JAR}" \
    --cookie "${JENKINS_COOKIE_JAR}" \
    --user "${JENKINS_ADMIN_USERNAME}:${JENKINS_ADMIN_PASSWORD}" \
    "${JENKINS_URL}/crumbIssuer/api/json" 2>/dev/null || true
}

CRUMB_JSON="$(get_crumb)"
if [[ -n "${CRUMB_JSON}" ]]; then
  CRUMB_FIELD="$(python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("crumbRequestField",""))' <<<"${CRUMB_JSON}")"
  CRUMB_VALUE="$(python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("crumb",""))' <<<"${CRUMB_JSON}")"
else
  CRUMB_FIELD=""
  CRUMB_VALUE=""
fi

curl_auth_args=(
  --silent
  --show-error
  --fail
  --cookie-jar "${JENKINS_COOKIE_JAR}"
  --cookie "${JENKINS_COOKIE_JAR}"
  --user "${JENKINS_ADMIN_USERNAME}:${JENKINS_ADMIN_PASSWORD}"
)

if [[ -n "${CRUMB_FIELD}" && -n "${CRUMB_VALUE}" ]]; then
  curl_auth_args+=(-H "${CRUMB_FIELD}: ${CRUMB_VALUE}")
fi

jenkins_credential_exists() {
  local cred_id="$1"
  curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    --user "${JENKINS_ADMIN_USERNAME}:${JENKINS_ADMIN_PASSWORD}" \
    "${JENKINS_URL}/credentials/store/system/domain/_/credential/${cred_id}/api/json" | grep -q '^200$'
}

delete_credential_if_exists() {
  local cred_id="$1"
  if jenkins_credential_exists "${cred_id}"; then
    echo "[bootstrap-jenkins] Replacing Jenkins credential ${cred_id}."
    curl "${curl_auth_args[@]}" \
      -X POST \
      "${JENKINS_URL}/credentials/store/system/domain/_/credential/${cred_id}/doDelete" \
      >/dev/null
  fi
}

create_secret_text_credential() {
  local cred_id="$1"
  local secret_value="$2"
  local description="$3"
  local xml_file="${TMP_DIR}/${cred_id}.xml"

  delete_credential_if_exists "${cred_id}"

  python3 - "$cred_id" "$secret_value" "$description" > "${xml_file}" <<'PY'
import sys
from xml.sax.saxutils import escape
cred_id, secret_value, description = sys.argv[1:4]
print(f"""<org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>{escape(cred_id)}</id>
  <description>{escape(description)}</description>
  <secret>{escape(secret_value)}</secret>
</org.jenkinsci.plugins.plaincredentials.impl.StringCredentialsImpl>""")
PY

  curl "${curl_auth_args[@]}" \
    -H "Content-Type: application/xml" \
    --data-binary "@${xml_file}" \
    "${JENKINS_URL}/credentials/store/system/domain/_/createCredentials" \
    >/dev/null
}

create_secret_file_credential() {
  local cred_id="$1"
  local file_path="$2"
  local file_name="$3"
  local description="$4"
  local xml_file="${TMP_DIR}/${cred_id}.xml"
  local secret_bytes

  delete_credential_if_exists "${cred_id}"

  secret_bytes="$(base64 -w 0 "${file_path}")"

  python3 - "$cred_id" "$file_name" "$description" "$secret_bytes" > "${xml_file}" <<'PY'
import sys
from xml.sax.saxutils import escape
cred_id, file_name, description, secret_bytes = sys.argv[1:5]
print(f"""<org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>{escape(cred_id)}</id>
  <description>{escape(description)}</description>
  <fileName>{escape(file_name)}</fileName>
  <secretBytes>{secret_bytes}</secretBytes>
</org.jenkinsci.plugins.plaincredentials.impl.FileCredentialsImpl>""")
PY

  curl "${curl_auth_args[@]}" \
    -H "Content-Type: application/xml" \
    --data-binary "@${xml_file}" \
    "${JENKINS_URL}/credentials/store/system/domain/_/createCredentials" \
    >/dev/null
}

create_username_password_credential() {
  local cred_id="$1"
  local username="$2"
  local password="$3"
  local description="$4"
  local xml_file="${TMP_DIR}/${cred_id}.xml"

  delete_credential_if_exists "${cred_id}"

  python3 - "$cred_id" "$username" "$password" "$description" > "${xml_file}" <<'PY'
import sys
from xml.sax.saxutils import escape
cred_id, username, password, description = sys.argv[1:5]
print(f"""<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>{escape(cred_id)}</id>
  <description>{escape(description)}</description>
  <username>{escape(username)}</username>
  <password>{escape(password)}</password>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>""")
PY

  curl "${curl_auth_args[@]}" \
    -H "Content-Type: application/xml" \
    --data-binary "@${xml_file}" \
    "${JENKINS_URL}/credentials/store/system/domain/_/createCredentials" \
    >/dev/null
}

job_exists() {
  curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    --user "${JENKINS_ADMIN_USERNAME}:${JENKINS_ADMIN_PASSWORD}" \
    "${JENKINS_URL}/job/${JOB_NAME}/api/json" | grep -q '^200$'
}

trigger_initial_build() {
  local headers_file="${TMP_DIR}/build.headers"

  curl "${curl_auth_args[@]}" \
    -D "${headers_file}" \
    -X POST \
    "${JENKINS_URL}/job/${JOB_NAME}/buildWithParameters?APP_DOMAIN=${APP_DOMAIN}" \
    >/dev/null

  awk 'BEGIN { IGNORECASE=1 } /^Location:/ { sub(/\r$/, "", $2); print $2; exit }' "${headers_file}"
}

wait_for_queue_item_to_start() {
  local queue_url="$1"
  local deadline=$(( $(date +%s) + INITIAL_BUILD_TIMEOUT_SECONDS ))

  while (( $(date +%s) < deadline )); do
    local queue_json executable_url executable_number cancelled why

    queue_json="$(curl "${curl_auth_args[@]}" "${queue_url}api/json")"
    executable_url="$(python3 -c 'import json,sys; data=json.load(sys.stdin); exe=data.get("executable") or {}; print(exe.get("url",""))' <<<"${queue_json}")"
    executable_number="$(python3 -c 'import json,sys; data=json.load(sys.stdin); exe=data.get("executable") or {}; print(exe.get("number",""))' <<<"${queue_json}")"
    cancelled="$(python3 -c 'import json,sys; data=json.load(sys.stdin); print("true" if data.get("cancelled") else "false")' <<<"${queue_json}")"
    why="$(python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("why",""))' <<<"${queue_json}")"

    if [[ -n "${executable_url}" && -n "${executable_number}" ]]; then
      printf '%s\t%s\n' "${executable_number}" "${executable_url}"
      return 0
    fi

    if [[ "${cancelled}" == "true" ]]; then
      echo "Initial Jenkins build was cancelled while in queue: ${why}" >&2
      return 1
    fi

    sleep 5
  done

  echo "Timed out waiting for Jenkins queue item to start." >&2
  return 1
}

wait_for_build_completion() {
  local build_number="$1"
  local build_url="$2"
  local deadline=$(( $(date +%s) + INITIAL_BUILD_TIMEOUT_SECONDS ))

  while (( $(date +%s) < deadline )); do
    local build_json is_building result

    build_json="$(curl "${curl_auth_args[@]}" "${build_url}api/json")"
    is_building="$(python3 -c 'import json,sys; data=json.load(sys.stdin); print("true" if data.get("building") else "false")' <<<"${build_json}")"
    result="$(python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("result",""))' <<<"${build_json}")"

    if [[ "${is_building}" != "true" ]]; then
      if [[ "${result}" == "SUCCESS" ]]; then
        echo "[bootstrap-jenkins] Initial Jenkins build #${build_number} finished successfully."
        return 0
      fi

      echo "Initial Jenkins build #${build_number} failed with result: ${result}" >&2
      echo "Build URL: ${build_url}" >&2
      return 1
    fi

    sleep 10
  done

  echo "Timed out waiting for Jenkins build #${build_number} to complete." >&2
  echo "Build URL: ${build_url}" >&2
  return 1
}

repo_url="$(git -C "${REPO_ROOT}" remote get-url origin)"
if [[ "${repo_url}" =~ ^git@github\.com:(.+)\.git$ ]]; then
  repo_url="https://github.com/${BASH_REMATCH[1]}.git"
fi

branch_name="$(git -C "${REPO_ROOT}" rev-parse --abbrev-ref HEAD)"
if [[ "${branch_name}" == "HEAD" ]]; then
  branch_name="main"
fi

JOB_CONFIG_XML="${TMP_DIR}/job-config.xml"

python3 - "${JOB_NAME}" "${repo_url}" "${branch_name}" "${JENKINS_GIT_CREDENTIALS_ID}" "${APP_DOMAIN}" > "${JOB_CONFIG_XML}" <<'PY'
import sys
from xml.sax.saxutils import escape

job_name, repo_url, branch_name, git_credentials_id, app_domain = sys.argv[1:6]

git_credentials_block = f"<credentialsId>{escape(git_credentials_id)}</credentialsId>" if git_credentials_id else "<credentialsId></credentialsId>"

xml = f"""<flow-definition plugin="workflow-job">
  <actions/>
  <description>Coin-Ops AKS deployment pipeline bootstrapped by script.</description>
  <keepDependencies>false</keepDependencies>
  <properties>
    <hudson.model.ParametersDefinitionProperty>
      <parameterDefinitions>
        <hudson.model.StringParameterDefinition>
          <name>APP_DOMAIN</name>
          <description>Base DNS zone, for example example.com</description>
          <defaultValue>{escape(app_domain)}</defaultValue>
          <trim>true</trim>
        </hudson.model.StringParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>APP_NAMESPACE</name>
          <description>AKS namespace for the release</description>
          <defaultValue>coin-ops</defaultValue>
          <trim>true</trim>
        </hudson.model.StringParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>INGRESS_TLS_SECRET_NAME</name>
          <description>TLS secret name used by the ingress</description>
          <defaultValue>coin-ops-tls</defaultValue>
          <trim>true</trim>
        </hudson.model.StringParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>INGRESS_CONTROLLER_SERVICE_NAMESPACE</name>
          <description>Namespace of the Traefik LoadBalancer service if ingress status is empty</description>
          <defaultValue>traefik</defaultValue>
          <trim>true</trim>
        </hudson.model.StringParameterDefinition>
        <hudson.model.StringParameterDefinition>
          <name>INGRESS_CONTROLLER_SERVICE_NAME</name>
          <description>Name of the Traefik LoadBalancer service if ingress status is empty</description>
          <defaultValue>traefik</defaultValue>
          <trim>true</trim>
        </hudson.model.StringParameterDefinition>
      </parameterDefinitions>
    </hudson.model.ParametersDefinitionProperty>
  </properties>
  <definition class="org.jenkinsci.plugins.workflow.cps.CpsScmFlowDefinition" plugin="workflow-cps">
    <scm class="hudson.plugins.git.GitSCM" plugin="git">
      <configVersion>2</configVersion>
      <userRemoteConfigs>
        <hudson.plugins.git.UserRemoteConfig>
          <url>{escape(repo_url)}</url>
          {git_credentials_block}
        </hudson.plugins.git.UserRemoteConfig>
      </userRemoteConfigs>
      <branches>
        <hudson.plugins.git.BranchSpec>
          <name>*/{escape(branch_name)}</name>
        </hudson.plugins.git.BranchSpec>
      </branches>
      <doGenerateSubmoduleConfigurations>false</doGenerateSubmoduleConfigurations>
      <submoduleCfg class="empty-list"/>
      <extensions/>
    </scm>
    <scriptPath>Jenkinsfile</scriptPath>
    <lightweight>false</lightweight>
  </definition>
  <triggers/>
  <disabled>false</disabled>
</flow-definition>
"""

print(xml)
PY

echo "[bootstrap-jenkins] Creating Jenkins credentials."
AcrPushUsername="$(az acr credential show --name "${ACR_NAME}" --query username -o tsv)"
AcrPushPassword="$(az acr credential show --name "${ACR_NAME}" --query 'passwords[0].value' -o tsv)"

create_secret_text_credential "AZURE_CLIENT_ID" "${ARM_CLIENT_ID}" "Azure service principal client ID"
create_secret_text_credential "AZURE_CLIENT_SECRET" "${ARM_CLIENT_SECRET}" "Azure service principal client secret"
create_secret_text_credential "AZURE_TENANT_ID" "${ARM_TENANT_ID}" "Azure tenant ID"
create_secret_text_credential "AZURE_SUBSCRIPTION_ID" "${ARM_SUBSCRIPTION_ID}" "Azure subscription ID"
create_secret_text_credential "ACR_NAME" "${ACR_NAME}" "Azure Container Registry name"
create_username_password_credential "acr-push" "${AcrPushUsername}" "${AcrPushPassword}" "ACR push credentials"
create_secret_text_credential "CLOUDFLARE_API_TOKEN" "${CLOUDFLARE_API_TOKEN}" "Cloudflare API token"
create_secret_text_credential "CLOUDFLARE_ZONE_ID" "${CLOUDFLARE_ZONE_ID}" "Cloudflare zone ID"
create_secret_file_credential "KUBECONFIG" "${KUBECONFIG_FILE}" "config" "AKS kubeconfig for Coin-Ops deployments"

echo "[bootstrap-jenkins] Creating or updating Jenkins job ${JOB_NAME}."
if job_exists; then
  curl "${curl_auth_args[@]}" \
    -H "Content-Type: application/xml" \
    --data-binary "@${JOB_CONFIG_XML}" \
    "${JENKINS_URL}/job/${JOB_NAME}/config.xml" \
    >/dev/null
else
  curl "${curl_auth_args[@]}" \
    -H "Content-Type: application/xml" \
    --data-binary "@${JOB_CONFIG_XML}" \
    "${JENKINS_URL}/createItem?name=${JOB_NAME}" \
    >/dev/null
fi

if [[ "${TRIGGER_INITIAL_BUILD}" == "true" ]]; then
  echo "[bootstrap-jenkins] Triggering initial Jenkins build."
  BUILD_QUEUE_URL="$(trigger_initial_build)"

  if [[ -z "${BUILD_QUEUE_URL}" ]]; then
    echo "Failed to determine Jenkins queue URL for initial build." >&2
    exit 1
  fi

  if [[ "${WAIT_FOR_INITIAL_BUILD}" == "true" ]]; then
    echo "[bootstrap-jenkins] Waiting for initial Jenkins build to start."
    IFS=$'\t' read -r BUILD_NUMBER BUILD_URL < <(wait_for_queue_item_to_start "${BUILD_QUEUE_URL}")
    echo "[bootstrap-jenkins] Waiting for initial Jenkins build #${BUILD_NUMBER} to complete."
    wait_for_build_completion "${BUILD_NUMBER}" "${BUILD_URL}"
  fi
fi

cat <<EOF
[bootstrap-jenkins] Completed successfully.
Jenkins URL: ${JENKINS_URL}
Job name: ${JOB_NAME}
Repo URL: ${repo_url}
Branch: ${branch_name}
APP_DOMAIN: ${APP_DOMAIN}

Created or updated Jenkins credentials:
- AZURE_CLIENT_ID
- AZURE_CLIENT_SECRET
- AZURE_TENANT_ID
- AZURE_SUBSCRIPTION_ID
- ACR_NAME
- acr-push
- CLOUDFLARE_API_TOKEN
- CLOUDFLARE_ZONE_ID
- KUBECONFIG
EOF
