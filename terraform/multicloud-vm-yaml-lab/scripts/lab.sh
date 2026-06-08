#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/../.." && pwd)"
ANSIBLE_INVENTORY_OUT="${ANSIBLE_INVENTORY_OUT:-$REPO_ROOT/ansible/inventory.cloud}"
AUTO_APPROVE="${AUTO_APPROVE:-false}"
LOAD_ENV="${LOAD_ENV:-true}"

CONFIG_FILE="$ROOT_DIR/config/lab.yaml"
S3_BACKEND_CONFIG_FILE="$ROOT_DIR/backend.hcl"
GENERATED_BACKEND_TF="$ROOT_DIR/backend.generated.tf"
GENERATED_AZURERM_BACKEND_CONFIG="$ROOT_DIR/backend.azurerm.generated.hcl"

yaml_cloud_value() {
  local cloud="$1"
  local key="$2"
  awk -v cloud="$cloud" -v key="$key" '
    /^clouds:[[:space:]]*$/ { in_clouds=1; next }
    in_clouds && $0 ~ "^[[:space:]]{2}" cloud ":[[:space:]]*$" { in_target=1; next }
    in_clouds && in_target && $0 ~ "^[[:space:]]{4}" key ":[[:space:]]*" {
      sub("^[[:space:]]{4}" key ":[[:space:]]*", "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
    in_clouds && in_target && $0 ~ "^[[:space:]]{2}[[:alnum:]_-]+:[[:space:]]*$" { in_target=0 }
    in_clouds && $0 !~ "^[[:space:]]" { in_clouds=0; in_target=0 }
  ' "$CONFIG_FILE"
}

yaml_secret_prefix() {
  awk '
    /^secrets:[[:space:]]*$/ { in_secrets=1; next }
    in_secrets && /^[[:space:]]{2}prefix:[[:space:]]*/ {
      sub(/^[[:space:]]{2}prefix:[[:space:]]*/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
    in_secrets && $0 !~ "^[[:space:]]" { in_secrets=0 }
  ' "$CONFIG_FILE"
}

yaml_secret_item() {
  local item="$1"
  awk -v item="$item" '
    /^secrets:[[:space:]]*$/ { in_secrets=1; next }
    in_secrets && /^[[:space:]]{2}items:[[:space:]]*$/ { in_items=1; next }
    in_secrets && in_items && $0 ~ "^[[:space:]]{4}" item ":[[:space:]]*" {
      sub("^[[:space:]]{4}" item ":[[:space:]]*", "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
    in_secrets && $0 !~ "^[[:space:]]" { in_secrets=0; in_items=0 }
  ' "$CONFIG_FILE"
}


read_cloud() {
  awk -F: '/^cloud:[[:space:]]*/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$ROOT_DIR/config/lab.yaml"
}

read_runtime_mode() {
  awk '
    /^runtime:[[:space:]]*$/ { in_runtime=1; next }
    in_runtime && /^[^[:space:]]/ { in_runtime=0 }
    in_runtime && /^[[:space:]]+mode:[[:space:]]*/ { sub(/^[[:space:]]+mode:[[:space:]]*/, ""); gsub(/[[:space:]]/, ""); print; exit }
  ' "$ROOT_DIR/config/lab.yaml"
}

normalize_runtime_mode() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '-' '_'
}

CLOUD="${CLOUD:-$(read_cloud)}"
RUNTIME_MODE="${RUNTIME_MODE:-$(read_runtime_mode)}"
RUNTIME_MODE="$(normalize_runtime_mode "${RUNTIME_MODE:-external}")"
LAB_WORKSPACE="${LAB_WORKSPACE:-$([ "$RUNTIME_MODE" = "cloud_native" ] && printf '%s-cloud-native' "$CLOUD" || printf '%s' "$CLOUD")}"
BACKEND_KIND="${BACKEND_KIND:-$([ "$CLOUD" = "azure" ] && printf 'azurerm' || printf 's3')}"
BACKEND_CONFIG_OVERRIDE="${BACKEND_CONFIG:-}"

AWS_PROFILE_NAME="${AWS_PROFILE:-$(yaml_cloud_value aws profile)}"
LOCATION="${LOCATION:-$(awk -F: '/^location:[[:space:]]*/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$CONFIG_FILE")}"
export LOCATION="${LOCATION:-eu_central}"
AWS_REGION_NAME="${AWS_REGION:-$(awk '
  /^catalog:[[:space:]]*$/ { in_catalog=1; next }
  in_catalog && /^[[:space:]]{2}locations:[[:space:]]*$/ { in_locations=1; next }
  in_locations && $0 ~ "^[[:space:]]{4}" ENVIRON["LOCATION"] ":[[:space:]]*$" { in_location=1; next }
  in_location && /^[[:space:]]{6}aws:[[:space:]]*$/ { in_aws=1; next }
  in_aws && /^[[:space:]]{8}region:[[:space:]]*/ { sub(/^[[:space:]]{8}region:[[:space:]]*/, ""); print; exit }
' "$CONFIG_FILE")}"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-$(yaml_cloud_value gcp project_id)}"
AZURE_RESOURCE_GROUP_NAME="${AZURE_RESOURCE_GROUP_NAME:-$(yaml_cloud_value azure resource_group_name)}"
AZURE_KEY_VAULT_NAME="${AZURE_KEY_VAULT_NAME:-$(yaml_cloud_value azure key_vault_name)}"
AZURE_STATE_LOCATION="${AZURE_STATE_LOCATION:-$(yaml_cloud_value azure state_location)}"
AZURE_STATE_RESOURCE_GROUP_NAME="${AZURE_STATE_RESOURCE_GROUP_NAME:-$(yaml_cloud_value azure state_resource_group_name)}"
AZURE_STATE_STORAGE_ACCOUNT_NAME="${AZURE_STATE_STORAGE_ACCOUNT_NAME:-$(yaml_cloud_value azure state_storage_account_name)}"
AZURE_STATE_CONTAINER_NAME="${AZURE_STATE_CONTAINER_NAME:-$(yaml_cloud_value azure state_container_name)}"
AZURE_STATE_KEY="${AZURE_STATE_KEY:-$(yaml_cloud_value azure state_key)}"
NAME_PREFIX="$(awk -F: '/^name_prefix:[[:space:]]*/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$CONFIG_FILE")"
SECRET_PREFIX="${SECRET_PREFIX:-$(yaml_secret_prefix)}"
SECRET_PREFIX="${SECRET_PREFIX:-$NAME_PREFIX}"
APP_INSTANCE_PROFILE_NAME="${APP_INSTANCE_PROFILE_NAME:-$(yaml_cloud_value aws app_instance_profile_name)}"
APP_INSTANCE_PROFILE_NAME="${APP_INSTANCE_PROFILE_NAME:-${NAME_PREFIX}-app-runtime-profile}"


usage() {
  cat <<USAGE
Usage: ./scripts/lab.sh <command>

Commands:
  doctor     check selected cloud credentials, bootstrap, and secret values
  secrets push  push local .env/exported secret values to cloud secret manager
  init       terraform init + select/create workspace from config/lab.yaml cloud/runtime
  plan       init, then terraform plan
  apply      init, terraform apply, then regenerate SSH config + Ansible inventory
  destroy     init, then terraform destroy
  azure repair-access  grant Terraform SP Key Vault data-plane access
  outputs    regenerate SSH config + Ansible inventory from current Terraform outputs
  ping       ansible ping all cloud hosts through generated inventory
  deploy     run Ansible provision + deploy using generated inventory
  k3s        run the k3s learning-cluster playbook (GCP only; apply first)
  k3s-app    deploy the real Coin-Ops app on k3s (GCP only; apply + k3s first)
  full       apply, regenerate outputs, then deploy

Useful env vars:
  AUTO_APPROVE=true       pass -auto-approve to terraform apply
  LAB_WORKSPACE=...      override auto workspace; cloud-native defaults to <cloud>-cloud-native
  BACKEND_KIND=...       override remote state backend kind; defaults to azurerm for cloud=azure, else s3
  LOAD_ENV=false          do not source repo .env if present
  SSH_KEY_PATH=...        required for deploy
  DB_PASSWORD=...         local source for secrets push and TF_VAR_db_password
  RABBITMQ_PASSWORD=...   local source for secrets push in external/postgres mode
  GHCR_TOKEN=...          optional local source for secrets push
  ARM_CLIENT_ID=...       Azure Terraform service-principal client ID
  ARM_CLIENT_SECRET=...   Azure Terraform service-principal secret
  ARM_TENANT_ID=...       Azure tenant ID
  ARM_SUBSCRIPTION_ID=... Azure subscription ID
  config/lab.yaml runtime.mode controls external/postgres/cloud-native

Examples:
  bash ./azure-bootstrap.sh
  source .env.azure
  ./scripts/lab.sh doctor
  ./scripts/lab.sh plan
  AUTO_APPROVE=true ./scripts/lab.sh apply
  SSH_KEY_PATH=~/.ssh/coinops_gcp_jump DB_PASSWORD=... ./scripts/lab.sh deploy
  AUTO_APPROVE=true SSH_KEY_PATH=~/.ssh/coinops_gcp_jump DB_PASSWORD=... ./scripts/lab.sh full
USAGE
}

load_env_file() {
  if [ "$LOAD_ENV" = "true" ] && [ -f "$REPO_ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$REPO_ROOT/.env"
    set +a
  fi
}

render_backend_files() {
  case "$BACKEND_KIND" in
    s3)
      cat > "$GENERATED_BACKEND_TF" <<'EOF'
terraform {
  backend "s3" {}
}
EOF
      ACTIVE_BACKEND_CONFIG="${BACKEND_CONFIG_OVERRIDE:-$S3_BACKEND_CONFIG_FILE}"
      ;;
    azurerm)
      : "${AZURE_STATE_LOCATION:?Set clouds.azure.state_location in config/lab.yaml or export AZURE_STATE_LOCATION.}"
      : "${AZURE_STATE_RESOURCE_GROUP_NAME:?Set clouds.azure.state_resource_group_name in config/lab.yaml or export AZURE_STATE_RESOURCE_GROUP_NAME.}"
      : "${AZURE_STATE_STORAGE_ACCOUNT_NAME:?Set clouds.azure.state_storage_account_name in config/lab.yaml or export AZURE_STATE_STORAGE_ACCOUNT_NAME.}"
      : "${AZURE_STATE_CONTAINER_NAME:?Set clouds.azure.state_container_name in config/lab.yaml or export AZURE_STATE_CONTAINER_NAME.}"
      : "${AZURE_STATE_KEY:?Set clouds.azure.state_key in config/lab.yaml or export AZURE_STATE_KEY.}"

      cat > "$GENERATED_BACKEND_TF" <<'EOF'
terraform {
  backend "azurerm" {}
}
EOF

      cat > "$GENERATED_AZURERM_BACKEND_CONFIG" <<EOF
resource_group_name  = "$AZURE_STATE_RESOURCE_GROUP_NAME"
storage_account_name = "$AZURE_STATE_STORAGE_ACCOUNT_NAME"
container_name       = "$AZURE_STATE_CONTAINER_NAME"
key                  = "$AZURE_STATE_KEY"
use_azuread_auth     = true
EOF
      ACTIVE_BACKEND_CONFIG="${BACKEND_CONFIG_OVERRIDE:-$GENERATED_AZURERM_BACKEND_CONFIG}"
      ;;
    *)
      echo "Unsupported BACKEND_KIND: $BACKEND_KIND" >&2
      exit 1
      ;;
  esac
}

ensure_azure_backend_storage() {
  az group create \
    --name "$AZURE_STATE_RESOURCE_GROUP_NAME" \
    --location "$AZURE_STATE_LOCATION" \
    --only-show-errors >/dev/null

  az storage account create \
    --name "$AZURE_STATE_STORAGE_ACCOUNT_NAME" \
    --resource-group "$AZURE_STATE_RESOURCE_GROUP_NAME" \
    --location "$AZURE_STATE_LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --allow-blob-public-access false \
    --min-tls-version TLS1_2 \
    --only-show-errors >/dev/null

  az storage container create \
    --name "$AZURE_STATE_CONTAINER_NAME" \
    --account-name "$AZURE_STATE_STORAGE_ACCOUNT_NAME" \
    --auth-mode login \
    --only-show-errors >/dev/null
}



require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "Missing required environment variable: $name" >&2
    return 1
  fi
}

azure_login_service_principal() {
  az account show --query id -o tsv 2>/dev/null | grep -qx "$ARM_SUBSCRIPTION_ID" && return 0
  az login \
    --service-principal \
    --username "$ARM_CLIENT_ID" \
    --password "$ARM_CLIENT_SECRET" \
    --tenant "$ARM_TENANT_ID" \
    >/dev/null
  az account set --subscription "$ARM_SUBSCRIPTION_ID"
}

azure_backend_container_scope() {
  local account_id
  account_id="$(az storage account show \
    --name "$AZURE_STATE_STORAGE_ACCOUNT_NAME" \
    --resource-group "$AZURE_STATE_RESOURCE_GROUP_NAME" \
    --query id \
    -o tsv 2>/dev/null || true)"
  [ -n "$account_id" ] || return 1
  printf '%s/blobServices/default/containers/%s' "$account_id" "$AZURE_STATE_CONTAINER_NAME"
}
source_azure_env_file() {
  if [ -f "$ROOT_DIR/.env.azure" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$ROOT_DIR/.env.azure"
    set +a
  fi
}

azure_repair_access() {
  source_azure_env_file
  require_env ARM_CLIENT_ID || exit 1
  require_env AZURE_RESOURCE_GROUP_NAME || exit 1
  require_env AZURE_KEY_VAULT_NAME || exit 1

  local sp_object_id
  sp_object_id="$(az ad sp show --id "$ARM_CLIENT_ID" --query id -o tsv)"

  echo "Granting Terraform SP Key Vault data-plane access: $AZURE_KEY_VAULT_NAME"
  az keyvault set-policy \
    --name "$AZURE_KEY_VAULT_NAME" \
    --resource-group "$AZURE_RESOURCE_GROUP_NAME" \
    --object-id "$sp_object_id" \
    --secret-permissions get list set delete recover purge \
    --certificate-permissions create delete get import list purge recover update \
    --only-show-errors >/dev/null

  echo "OK Key Vault access policy for Terraform SP object: $sp_object_id"
}
aws_cli() {
  aws --profile "$AWS_PROFILE_NAME" --region "$AWS_REGION_NAME" "$@"
}

gcp_secret_id() {
  local item="$1"
  printf '%s-%s' "$SECRET_PREFIX" "$item" | tr '/_' '--'
}

azure_secret_name() {
  local item="$1"
  printf '%s' "$item" | tr '/_' '--'
}

aws_secret_name() {
  local item="$1"
  printf '%s/%s' "${SECRET_PREFIX%/}" "$item"
}

secret_item_name() {
  local key="$1"
  local fallback="$2"
  local value
  value="$(yaml_secret_item "$key")"
  printf '%s' "${value:-$fallback}"
}

push_aws_secret() {
  local name="$1"
  local value="$2"
  if aws_cli secretsmanager describe-secret --secret-id "$name" >/dev/null 2>&1; then
    aws_cli secretsmanager put-secret-value --secret-id "$name" --secret-string "$value" --query VersionId --output text >/dev/null
  else
    aws_cli secretsmanager create-secret --name "$name" --secret-string "$value" --query ARN --output text >/dev/null
  fi
  echo "Pushed AWS secret: $name"
}

push_gcp_secret() {
  local secret_id="$1"
  local value="$2"
  if ! gcloud secrets describe "$secret_id" --project "$GCP_PROJECT_ID" >/dev/null 2>&1; then
    gcloud secrets create "$secret_id" --project "$GCP_PROJECT_ID" --replication-policy automatic >/dev/null
  fi
  printf '%s' "$value" | gcloud secrets versions add "$secret_id" --project "$GCP_PROJECT_ID" --data-file - >/dev/null
  echo "Pushed GCP secret: $secret_id"
}

push_azure_secret() {
  local secret_name="$1"
  local value="$2"
  az keyvault secret set --vault-name "$AZURE_KEY_VAULT_NAME" --name "$secret_name" --value "$value" --only-show-errors >/dev/null
  echo "Pushed Azure Key Vault secret: $secret_name"
}

push_secret_value() {
  local key="$1"
  local env_name="$2"
  local fallback_name="$3"
  local required="${4:-true}"
  local value="${!env_name:-}"
  local item_name
  item_name="$(secret_item_name "$key" "$fallback_name")"
  if [ -z "$value" ]; then
    if [ "$required" = "true" ]; then
      echo "Missing $env_name. Set it in .env or export it before './scripts/lab.sh secrets push'." >&2
      exit 1
    fi
    echo "Skipping optional secret $key because $env_name is empty."
    return
  fi
  case "$CLOUD" in
    aws) push_aws_secret "$(aws_secret_name "$item_name")" "$value" ;;
    gcp) push_gcp_secret "$(gcp_secret_id "$item_name")" "$value" ;;
    azure) push_azure_secret "$(azure_secret_name "$item_name")" "$value" ;;
    *) echo "Unsupported cloud: $CLOUD" >&2; exit 1 ;;
  esac
}

ensure_secret_containers() {
  terraform_init
  cd "$ROOT_DIR"
  case "$CLOUD" in
    aws) terraform apply -target='module.aws[0].module.secrets' -auto-approve ;;
    gcp) terraform apply -target='module.gcp[0].module.secrets' -auto-approve ;;
    azure) terraform apply -target='module.azure[0].module.secrets' -auto-approve ;;
  esac
}

secrets_push() {
  load_env_file
  ensure_secret_containers
  push_secret_value db_password DB_PASSWORD db-password true
  if [ "$RUNTIME_MODE" != "cloud_native" ]; then
    push_secret_value rabbitmq_password RABBITMQ_PASSWORD rabbitmq-password true
  fi
  push_secret_value ghcr_token GHCR_TOKEN ghcr-token false
  # Cloudflare API token for cert-manager's DNS-01 solver (optional — only when
  # issuing Let's Encrypt certs). Same token works if it has Zone:DNS:Edit.
  push_secret_value cloudflare_token CLOUDFLARE_TOKEN cloudflare-token false
}

check_secret_value_exists() {
  local key="$1"
  local fallback_name="$2"
  local item_name
  item_name="$(secret_item_name "$key" "$fallback_name")"
  case "$CLOUD" in
    aws) aws_cli secretsmanager get-secret-value --secret-id "$(aws_secret_name "$item_name")" >/dev/null ;;
    gcp) gcloud secrets versions access latest --secret "$(gcp_secret_id "$item_name")" --project "$GCP_PROJECT_ID" >/dev/null ;;
    azure) az keyvault secret show --vault-name "$AZURE_KEY_VAULT_NAME" --name "$(azure_secret_name "$item_name")" --query value -o tsv --only-show-errors >/dev/null ;;
  esac
}

doctor() {
  local failed=false
  echo "Cloud: $CLOUD"
  echo "Workspace: $LAB_WORKSPACE"
  echo "State backend: $BACKEND_KIND"
  case "$CLOUD" in
    aws)
      aws_cli sts get-caller-identity --query Arn --output text
      for role in AWSServiceRoleForElasticLoadBalancing AWSServiceRoleForElastiCache AWSServiceRoleForRDS; do
        if aws --profile "$AWS_PROFILE_NAME" iam get-role --role-name "$role" >/dev/null 2>&1; then
          echo "OK service-linked role: $role"
        else
          echo "Missing service-linked role: $role. Run aws-iam/bootstrap.sh once with an admin profile."
          failed=true
        fi
      done
      if aws --profile "$AWS_PROFILE_NAME" iam get-instance-profile --instance-profile-name "$APP_INSTANCE_PROFILE_NAME" >/dev/null 2>&1; then
        echo "OK app instance profile: $APP_INSTANCE_PROFILE_NAME"
      else
        echo "Missing app instance profile: $APP_INSTANCE_PROFILE_NAME. Run aws-iam/bootstrap.sh once with an admin profile."
        failed=true
      fi
      ;;
    gcp)
      gcloud projects describe "$GCP_PROJECT_ID" --format='value(projectId)'
      ;;
    azure)
      command -v az >/dev/null || { echo "Missing az CLI"; exit 1; }
      require_env ARM_CLIENT_ID || failed=true
      require_env ARM_CLIENT_SECRET || failed=true
      require_env ARM_TENANT_ID || failed=true
      require_env ARM_SUBSCRIPTION_ID || failed=true
      if [ ! -f "${SSH_KEY_PATH:-$HOME/.ssh/coinops_gcp_jump}.pub" ]; then
        echo "Missing SSH public key: ${SSH_KEY_PATH:-$HOME/.ssh/coinops_gcp_jump}.pub. Run ./azure-bootstrap.sh first."
        failed=true
      fi
      if [ "$failed" != "true" ]; then
        azure_login_service_principal
        az account show --query '{name:name, id:id, tenantId:tenantId}' -o table
        if az group show --name "$AZURE_RESOURCE_GROUP_NAME" --only-show-errors >/dev/null 2>&1; then
          echo "OK workload resource group: $AZURE_RESOURCE_GROUP_NAME"
        else
          echo "Missing workload resource group: $AZURE_RESOURCE_GROUP_NAME. Run ./azure-bootstrap.sh first."
          failed=true
        fi
        if az group show --name "$AZURE_STATE_RESOURCE_GROUP_NAME" --only-show-errors >/dev/null 2>&1; then
          echo "OK tfstate resource group: $AZURE_STATE_RESOURCE_GROUP_NAME"
        else
          echo "Missing tfstate resource group: $AZURE_STATE_RESOURCE_GROUP_NAME. Run ./azure-bootstrap.sh first."
          failed=true
        fi
        container_exists="$(az storage container exists --account-name "$AZURE_STATE_STORAGE_ACCOUNT_NAME" --name "$AZURE_STATE_CONTAINER_NAME" --auth-mode login --query exists -o tsv 2>/dev/null || printf 'false')"
        if [ "$container_exists" = "true" ]; then
          echo "OK tfstate container access: $AZURE_STATE_CONTAINER_NAME"
        else
          echo "Cannot access tfstate container with Azure AD: $AZURE_STATE_CONTAINER_NAME"
          failed=true
        fi
        workload_scope="/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$AZURE_RESOURCE_GROUP_NAME"
        tfstate_container_scope="$(azure_backend_container_scope || true)"
        contributor_count="$(az role assignment list --assignee "$ARM_CLIENT_ID" --role Contributor --scope "$workload_scope" --query 'length(@)' -o tsv 2>/dev/null || printf '0')"
        uaa_count="$(az role assignment list --assignee "$ARM_CLIENT_ID" --role 'User Access Administrator' --scope "$workload_scope" --query 'length(@)' -o tsv 2>/dev/null || printf '0')"
        blob_count=0
        if [ -n "$tfstate_container_scope" ]; then
          blob_count="$(az role assignment list --assignee "$ARM_CLIENT_ID" --role 'Storage Blob Data Contributor' --scope "$tfstate_container_scope" --query 'length(@)' -o tsv 2>/dev/null || printf '0')"
        fi
        [ "${contributor_count:-0}" != "0" ] && echo "OK role: Contributor on $AZURE_RESOURCE_GROUP_NAME" || { echo "Missing role: Contributor on $AZURE_RESOURCE_GROUP_NAME"; failed=true; }
        [ "${uaa_count:-0}" != "0" ] && echo "OK role: User Access Administrator on $AZURE_RESOURCE_GROUP_NAME" || { echo "Missing role: User Access Administrator on $AZURE_RESOURCE_GROUP_NAME"; failed=true; }
        [ "${blob_count:-0}" != "0" ] && echo "OK role: Storage Blob Data Contributor for tfstate" || { echo "Missing role: Storage Blob Data Contributor for tfstate"; failed=true; }
      fi
      ;;
  esac
  secret_specs=("db_password db-password")
  if [ "$RUNTIME_MODE" != "cloud_native" ]; then
    secret_specs+=("rabbitmq_password rabbitmq-password")
  fi
  for spec in "${secret_specs[@]}"; do
    set -- $spec
    if check_secret_value_exists "$1" "$2" >/dev/null 2>&1; then
      echo "OK secret value: $1"
    else
      echo "Missing secret value: $1. Run './scripts/lab.sh secrets push'."
    fi
  done
  if [ "$failed" = "true" ]; then
    exit 1
  fi
}

terraform_init() {
  load_env_file
  if [ -n "${DB_PASSWORD:-}" ]; then
    export TF_VAR_db_password="$DB_PASSWORD"
  fi
  cd "$ROOT_DIR"
  render_backend_files
  # Default: migrate state when the backend changes. Set RECONFIGURE=true to init
  # the backend fresh WITHOUT migrating — use when switching clouds and you do NOT
  # want to copy another cloud's state (e.g. leave the AWS s3 state alone while
  # standing up the Azure azurerm backend).
  if [ "${RECONFIGURE:-false}" = "true" ]; then
    terraform init -backend-config="$ACTIVE_BACKEND_CONFIG" -reconfigure
  else
    terraform init -backend-config="$ACTIVE_BACKEND_CONFIG" -migrate-state -force-copy
  fi
  terraform workspace select "$LAB_WORKSPACE" || terraform workspace new "$LAB_WORKSPACE"
  if [ "$CLOUD" = "azure" ] && terraform state list 2>/dev/null | grep -qx 'module.azure[0].module.network.azurerm_resource_group.this'; then
    echo "Removing bootstrap-owned Azure resource group from Terraform state"
    terraform state rm 'module.azure[0].module.network.azurerm_resource_group.this' >/dev/null
  fi
}

terraform_apply() {
  cd "$ROOT_DIR"
  if [ "$AUTO_APPROVE" = "true" ]; then
    terraform apply -auto-approve
  else
    terraform apply
  fi
}

terraform_destroy() {
  cd "$ROOT_DIR"
  if [ "$AUTO_APPROVE" = "true" ]; then
    terraform destroy -auto-approve
  else
    terraform destroy
  fi
}
write_outputs() {
  cd "$ROOT_DIR"
  CLOUD="$CLOUD" "$ROOT_DIR/scripts/post-apply.sh"
}

ansible_deploy() {
  load_env_file
  : "${SSH_KEY_PATH:?Set SSH_KEY_PATH or put it in .env}"
  export RUNTIME_BACKEND="$RUNTIME_MODE"
  cd "$REPO_ROOT"
  # cloud-deploy.yml is now a single full-lifecycle playbook (provision +
  # deploy via meta-roles); the old cloud-provision.yml was folded in.
  ansible-playbook -i "$ANSIBLE_INVENTORY_OUT" ansible/cloud-deploy.yml
}

ansible_k3s() {
  load_env_file
  : "${SSH_KEY_PATH:?Set SSH_KEY_PATH or put it in .env}"
  if [ "$CLOUD" != "gcp" ] && [ "$CLOUD" != "azure" ]; then
    echo "k3s runs only on the k3s clouds (gcp or azure); config/lab.yaml has cloud=$CLOUD." >&2
    echo "Set 'cloud: gcp' or 'cloud: azure' in config/lab.yaml, apply, then re-run." >&2
    exit 2
  fi
  export RUNTIME_BACKEND="$RUNTIME_MODE"
  cd "$REPO_ROOT"
  ansible-playbook -i "$ANSIBLE_INVENTORY_OUT" ansible/k3s-up.yml
}

ansible_k3s_app() {
  load_env_file
  : "${SSH_KEY_PATH:?Set SSH_KEY_PATH or put it in .env}"
  if [ "$CLOUD" != "gcp" ] && [ "$CLOUD" != "azure" ]; then
    echo "k3s-app runs only on the k3s clouds (gcp or azure); config/lab.yaml has cloud=$CLOUD." >&2
    echo "Set 'cloud: gcp' or 'cloud: azure' in config/lab.yaml, then apply + k3s, then re-run." >&2
    exit 2
  fi
  export RUNTIME_BACKEND="$RUNTIME_MODE"

  # Pass the Azure observability backend (workspace ids, App Insights connstr,
  # Grafana/Prometheus endpoints) to the k3s_observability role. Captured here
  # from the terraform output while we're still able to chdir into the tf dir.
  # Safe no-op when the output is null/absent (obs disabled or non-Azure): we
  # pass nothing and the role's disabled defaults take over. The App Insights
  # connstr ends up in the process argv (visible in `ps`) — acceptable for a
  # student lab; every consumer of it in the role is no_log.
  # When the terraform observability output exists (observability.enabled: true),
  # also flip the role's master gate on — one switch (the tf toggle) drives both
  # the Azure backend and the in-cluster automation.
  local obs_extra=""
  local obs_json
  obs_json="$(terraform -chdir="$ROOT_DIR" output -json observability 2>/dev/null || true)"
  if [ -n "$obs_json" ] && [ "$obs_json" != "null" ]; then
    obs_extra="-e k3s_observability_enabled=true -e tf_observability=$obs_json"
  fi

  cd "$REPO_ROOT"
  # shellcheck disable=SC2086  # obs_extra is intentionally word-split into args
  ansible-playbook -i "$ANSIBLE_INVENTORY_OUT" ansible/k3s-app.yml $obs_extra
}

cmd="${1:-}"
case "$cmd" in
  doctor)
    doctor
    ;;
  secrets)
    case "${2:-}" in
      push) secrets_push ;;
      *) echo "Usage: ./scripts/lab.sh secrets push" >&2; exit 2 ;;
    esac
    ;;
  azure)
    case "${2:-}" in
      repair-access) azure_repair_access ;;
      *) echo "Usage: ./scripts/lab.sh azure repair-access" >&2; exit 2 ;;
    esac
    ;;
  init)
    terraform_init
    ;;
  plan)
    terraform_init
    cd "$ROOT_DIR"
    terraform plan
    ;;
  apply)
    terraform_init
    terraform_apply
    write_outputs
    ;;
  destroy)
    terraform_init
    terraform_destroy
    ;;
  outputs)
    write_outputs
    ;;
  ping)
    cd "$REPO_ROOT"
    ansible -i "$ANSIBLE_INVENTORY_OUT" all -m ping
    ;;
  deploy)
    write_outputs
    ansible_deploy
    ;;
  k3s)
    write_outputs
    ansible_k3s
    ;;
  k3s-app)
    write_outputs
    ansible_k3s_app
    ;;
  full)
    terraform_init
    terraform_apply
    write_outputs
    ansible_deploy
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac
