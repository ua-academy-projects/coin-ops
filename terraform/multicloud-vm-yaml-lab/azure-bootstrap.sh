#!/usr/bin/env bash
set -euo pipefail

# One-time Azure bootstrap for the lab.
#
# Run this with a human/admin Azure login (`az login`). It creates the few
# things normal least-privilege Terraform cannot safely create by itself:
# resource groups, remote state storage, and the Terraform service principal.
# After this script writes `.env.azure`, normal `lab.sh plan/apply` should run
# from ARM_* service-principal credentials and should not depend on your human
# Azure session.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/config/lab.yaml}"

# Tiny YAML readers for this repo's simple lab.yaml shape. They intentionally
# avoid adding yq as a dependency for bootstrap.

yaml_top_value() {
  local key="$1"
  awk -F: -v key="$key" '$1 == key { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }' "$CONFIG_FILE"
}

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
# Quote values before writing shell exports into .env.azure.
shell_quote() {
  local value="$1"
  printf "'%s'" "$(printf '%s' "$value" | sed "s/'/'\\\\''/g")"
}

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Missing required command: $name" >&2
    exit 1
  fi
}

# Role assignment creation is eventually consistent in Azure, so the helper is
# idempotent and retries instead of creating duplicate assignments.
role_assignment_exists() {
  local assignee="$1"
  local role="$2"
  local scope="$3"
  local count
  count="$(az role assignment list \
    --assignee "$assignee" \
    --role "$role" \
    --scope "$scope" \
    --query 'length(@)' \
    -o tsv 2>/dev/null || printf '0')"
  [ "${count:-0}" != "0" ]
}

ensure_role_assignment() {
  local assignee="$1"
  local role="$2"
  local scope="$3"

  if role_assignment_exists "$assignee" "$role" "$scope"; then
    echo "OK role assignment: $role on $scope"
    return
  fi

  echo "Creating role assignment: $role on $scope"
  local attempt
  for attempt in 1 2 3 4 5 6; do
    if az role assignment create \
      --assignee "$assignee" \
      --role "$role" \
      --scope "$scope" \
      >/dev/null; then
      echo "Created role assignment: $role"
      return
    fi
    echo "Role assignment create failed, retrying in $((attempt * 5))s..." >&2
    sleep $((attempt * 5))
  done

  echo "Failed to create role assignment: $role on $scope" >&2
  exit 1
}

# Fail early if the local machine cannot perform bootstrap work.
require_command az
require_command ssh-keygen
require_command python3

# Defaults come from config/lab.yaml, but every value can be overridden from the
# shell for experiments or a different student subscription.
NAME_PREFIX="${NAME_PREFIX:-$(yaml_top_value name_prefix)}"
NAME_PREFIX="${NAME_PREFIX:-coinops-lab}"
NAME_PREFIX_COMPACT="$(printf '%s' "$NAME_PREFIX" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"

AZURE_LOCATION="${AZURE_LOCATION:-$(yaml_cloud_value azure state_location)}"
AZURE_LOCATION="${AZURE_LOCATION:-$(yaml_cloud_value azure location)}"
AZURE_LOCATION="${AZURE_LOCATION:-canadacentral}"
AZURE_WORKLOAD_RESOURCE_GROUP="${AZURE_WORKLOAD_RESOURCE_GROUP:-$(yaml_cloud_value azure resource_group_name)}"
AZURE_WORKLOAD_RESOURCE_GROUP="${AZURE_WORKLOAD_RESOURCE_GROUP:-${NAME_PREFIX}-rg}"
AZURE_KEY_VAULT_NAME="${AZURE_KEY_VAULT_NAME:-$(yaml_cloud_value azure key_vault_name)}"
AZURE_STATE_RESOURCE_GROUP_NAME="${AZURE_STATE_RESOURCE_GROUP_NAME:-$(yaml_cloud_value azure state_resource_group_name)}"
AZURE_STATE_RESOURCE_GROUP_NAME="${AZURE_STATE_RESOURCE_GROUP_NAME:-coinops-tfstate-rg}"
AZURE_STATE_STORAGE_ACCOUNT_NAME="${AZURE_STATE_STORAGE_ACCOUNT_NAME:-$(yaml_cloud_value azure state_storage_account_name)}"
AZURE_STATE_STORAGE_ACCOUNT_NAME="${AZURE_STATE_STORAGE_ACCOUNT_NAME:-${NAME_PREFIX_COMPACT}tfstate}"
AZURE_STATE_CONTAINER_NAME="${AZURE_STATE_CONTAINER_NAME:-$(yaml_cloud_value azure state_container_name)}"
AZURE_STATE_CONTAINER_NAME="${AZURE_STATE_CONTAINER_NAME:-tfstate}"
AZURE_STATE_KEY="${AZURE_STATE_KEY:-$(yaml_cloud_value azure state_key)}"
AZURE_STATE_KEY="${AZURE_STATE_KEY:-multicloud-vm-yaml-lab/terraform.tfstate}"
AZURE_TERRAFORM_SP_NAME="${AZURE_TERRAFORM_SP_NAME:-coinops-terraform-sp}"
AZURE_TERRAFORM_SECRET_YEARS="${AZURE_TERRAFORM_SECRET_YEARS:-1}"
AZURE_ENV_FILE="${AZURE_ENV_FILE:-$ROOT_DIR/.env.azure}"
BACKEND_CONFIG_FILE="${BACKEND_CONFIG_FILE:-$ROOT_DIR/backend.azurerm.generated.hcl}"
GENERATED_BACKEND_TF="${GENERATED_BACKEND_TF:-$ROOT_DIR/backend.generated.tf}"
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/coinops_gcp_jump}"

# Bootstrap itself needs a human/admin Azure CLI session. The service principal
# created below is what Terraform uses afterward.
if ! az account show >/dev/null 2>&1; then
  echo "Azure CLI is not logged in. Run 'az login' with a bootstrap/admin user first." >&2
  exit 1
fi

AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"
AZURE_TENANT_ID="${AZURE_TENANT_ID:-$(az account show --query tenantId -o tsv)}"

az account set --subscription "$AZURE_SUBSCRIPTION_ID"

echo "Bootstrap subscription: $AZURE_SUBSCRIPTION_ID"
echo "Bootstrap tenant:       $AZURE_TENANT_ID"
echo "Location:               $AZURE_LOCATION"
echo "Workload RG:            $AZURE_WORKLOAD_RESOURCE_GROUP"
echo "Key Vault:              ${AZURE_KEY_VAULT_NAME:-<created by Terraform>}"
echo "Tfstate RG:             $AZURE_STATE_RESOURCE_GROUP_NAME"
echo "Tfstate storage:        $AZURE_STATE_STORAGE_ACCOUNT_NAME"
echo "Terraform SP:           $AZURE_TERRAFORM_SP_NAME"

# Provider registration is subscription-scoped. A resource-group-scoped
# Terraform SP should not need that permission, so bootstrap does it once.
for provider in \
  Microsoft.Authorization \
  Microsoft.Cache \
  Microsoft.Compute \
  Microsoft.DBforPostgreSQL \
  Microsoft.KeyVault \
  Microsoft.ManagedIdentity \
  Microsoft.Network \
  Microsoft.ServiceBus \
  Microsoft.Storage
do
  echo "Registering provider: $provider"
  az provider register --namespace "$provider" >/dev/null
done

# Resource group lifecycle belongs to bootstrap. Terraform manages resources
# inside the workload RG, but should not destroy/recreate the RG itself.
echo "Ensuring resource groups..."
az group create --name "$AZURE_STATE_RESOURCE_GROUP_NAME" --location "$AZURE_LOCATION" >/dev/null
az group create --name "$AZURE_WORKLOAD_RESOURCE_GROUP" --location "$AZURE_LOCATION" >/dev/null

# Remote state storage also belongs to bootstrap because Terraform needs state
# before it can manage anything else.
if az storage account show \
  --name "$AZURE_STATE_STORAGE_ACCOUNT_NAME" \
  --resource-group "$AZURE_STATE_RESOURCE_GROUP_NAME" \
  >/dev/null 2>&1; then
  echo "OK storage account: $AZURE_STATE_STORAGE_ACCOUNT_NAME"
else
  echo "Creating storage account: $AZURE_STATE_STORAGE_ACCOUNT_NAME"
  az storage account create \
    --name "$AZURE_STATE_STORAGE_ACCOUNT_NAME" \
    --resource-group "$AZURE_STATE_RESOURCE_GROUP_NAME" \
    --location "$AZURE_LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --https-only true \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false \
    >/dev/null
fi

# The bootstrap admin can use an account key to create the container. Normal
# Terraform later uses Azure AD via Storage Blob Data Contributor.
storage_key="$(az storage account keys list \
  --account-name "$AZURE_STATE_STORAGE_ACCOUNT_NAME" \
  --resource-group "$AZURE_STATE_RESOURCE_GROUP_NAME" \
  --query '[0].value' \
  -o tsv)"

az storage container create \
  --name "$AZURE_STATE_CONTAINER_NAME" \
  --account-name "$AZURE_STATE_STORAGE_ACCOUNT_NAME" \
  --account-key "$storage_key" \
  >/dev/null
echo "OK tfstate container: $AZURE_STATE_CONTAINER_NAME"

# Create or reuse the dedicated Terraform identity. This is Azure's closest
# equivalent to an AWS IAM user with access keys or a GCP service account.
app_id="$(az ad sp list \
  --display-name "$AZURE_TERRAFORM_SP_NAME" \
  --query '[0].appId' \
  -o tsv)"
[ "$app_id" = "None" ] && app_id=""

# If .env.azure already contains the matching secret, keep it. Otherwise create
# a fresh client secret with a clear expiry.
client_secret=""
if [ -n "$app_id" ]; then
  echo "Reusing service principal: $AZURE_TERRAFORM_SP_NAME ($app_id)"
  if [ -f "$AZURE_ENV_FILE" ]; then
    existing_client_id="$(set +u; . "$AZURE_ENV_FILE" >/dev/null 2>&1; printf '%s' "${ARM_CLIENT_ID:-}")"
    existing_client_secret="$(set +u; . "$AZURE_ENV_FILE" >/dev/null 2>&1; printf '%s' "${ARM_CLIENT_SECRET:-}")"
    if [ "$existing_client_id" = "$app_id" ] && [ -n "$existing_client_secret" ]; then
      client_secret="$existing_client_secret"
      echo "Reusing existing local client secret from $AZURE_ENV_FILE"
    fi
  fi
else
  echo "Creating service principal: $AZURE_TERRAFORM_SP_NAME"
  sp_json="$(az ad sp create-for-rbac --name "$AZURE_TERRAFORM_SP_NAME" --skip-assignment -o json)"
  app_id="$(printf '%s' "$sp_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["appId"])')"
  client_secret="$(printf '%s' "$sp_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')"
fi

if [ -z "$client_secret" ]; then
  echo "Creating a new client secret for $AZURE_TERRAFORM_SP_NAME"
  credential_json="$(az ad sp credential reset \
    --id "$app_id" \
    --years "$AZURE_TERRAFORM_SECRET_YEARS" \
    -o json)"
  client_secret="$(printf '%s' "$credential_json" | python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])')"
fi

# Least privilege for Terraform:
# - Contributor lets it create/update infrastructure inside the workload RG.
# - User Access Administrator lets it assign roles to managed identities there.
# - Storage Blob Data Contributor lets it read/write remote state only.
sp_object_id="$(az ad sp show --id "$app_id" --query id -o tsv)"

# Existing Key Vaults enforce data-plane access separately from ARM roles.
# If the vault already exists, grant the Terraform SP enough permissions to
# refresh/manage lab secrets and the self-signed Application Gateway cert.
if [ -n "${AZURE_KEY_VAULT_NAME:-}" ] && az keyvault show \
  --name "$AZURE_KEY_VAULT_NAME" \
  --resource-group "$AZURE_WORKLOAD_RESOURCE_GROUP" \
  --only-show-errors >/dev/null 2>&1; then
  echo "Ensuring Terraform SP Key Vault data-plane access: $AZURE_KEY_VAULT_NAME"
  az keyvault set-policy \
    --name "$AZURE_KEY_VAULT_NAME" \
    --resource-group "$AZURE_WORKLOAD_RESOURCE_GROUP" \
    --object-id "$sp_object_id" \
    --secret-permissions get list set delete recover purge \
    --certificate-permissions create delete get import list purge recover update \
    --only-show-errors >/dev/null
fi
workload_scope="/subscriptions/$AZURE_SUBSCRIPTION_ID/resourceGroups/$AZURE_WORKLOAD_RESOURCE_GROUP"
storage_account_id="$(az storage account show \
  --name "$AZURE_STATE_STORAGE_ACCOUNT_NAME" \
  --resource-group "$AZURE_STATE_RESOURCE_GROUP_NAME" \
  --query id \
  -o tsv)"
container_scope="$storage_account_id/blobServices/default/containers/$AZURE_STATE_CONTAINER_NAME"

ensure_role_assignment "$app_id" "Contributor" "$workload_scope"
ensure_role_assignment "$app_id" "User Access Administrator" "$workload_scope"
ensure_role_assignment "$app_id" "Storage Blob Data Contributor" "$container_scope"

# The lab deploy path needs this SSH key for Ansible/bastion access.
if [ ! -f "$SSH_KEY_PATH" ]; then
  echo "Generating SSH key: $SSH_KEY_PATH"
  mkdir -p "$(dirname "$SSH_KEY_PATH")"
  ssh-keygen -t ed25519 -C "${NAME_PREFIX}-ssh" -f "$SSH_KEY_PATH" -N ""
elif [ ! -f "$SSH_KEY_PATH.pub" ]; then
  echo "Regenerating missing public key: $SSH_KEY_PATH.pub"
  ssh-keygen -y -f "$SSH_KEY_PATH" > "$SSH_KEY_PATH.pub"
else
  echo "OK SSH key: $SSH_KEY_PATH"
fi

# Generate the Azure backend files consumed by scripts/lab.sh during terraform
# init. These are local machine artifacts, not source-controlled config.
cat > "$GENERATED_BACKEND_TF" <<EOF
terraform {
  backend "azurerm" {}
}
EOF
chmod 0600 "$GENERATED_BACKEND_TF"

cat > "$BACKEND_CONFIG_FILE" <<EOF
resource_group_name  = "$AZURE_STATE_RESOURCE_GROUP_NAME"
storage_account_name = "$AZURE_STATE_STORAGE_ACCOUNT_NAME"
container_name       = "$AZURE_STATE_CONTAINER_NAME"
key                  = "$AZURE_STATE_KEY"
use_azuread_auth     = true
subscription_id      = "$AZURE_SUBSCRIPTION_ID"
tenant_id            = "$AZURE_TENANT_ID"
EOF
chmod 0600 "$BACKEND_CONFIG_FILE"
echo "Wrote backend config: $BACKEND_CONFIG_FILE"

# Write the normal Terraform credentials. Source this file after bootstrap:
#   source .env.azure
cat > "$AZURE_ENV_FILE" <<EOF
# Generated by azure-bootstrap.sh. Do not commit this file.
export ARM_CLIENT_ID=$(shell_quote "$app_id")
export ARM_CLIENT_SECRET=$(shell_quote "$client_secret")
export ARM_TENANT_ID=$(shell_quote "$AZURE_TENANT_ID")
export ARM_SUBSCRIPTION_ID=$(shell_quote "$AZURE_SUBSCRIPTION_ID")
export AZURE_RESOURCE_GROUP_NAME=$(shell_quote "$AZURE_WORKLOAD_RESOURCE_GROUP")
export AZURE_WORKLOAD_RESOURCE_GROUP=$(shell_quote "$AZURE_WORKLOAD_RESOURCE_GROUP")
export AZURE_STATE_LOCATION=$(shell_quote "$AZURE_LOCATION")
export AZURE_STATE_RESOURCE_GROUP_NAME=$(shell_quote "$AZURE_STATE_RESOURCE_GROUP_NAME")
export AZURE_STATE_STORAGE_ACCOUNT_NAME=$(shell_quote "$AZURE_STATE_STORAGE_ACCOUNT_NAME")
export AZURE_STATE_CONTAINER_NAME=$(shell_quote "$AZURE_STATE_CONTAINER_NAME")
export AZURE_STATE_KEY=$(shell_quote "$AZURE_STATE_KEY")
export SSH_KEY_PATH=$(shell_quote "$SSH_KEY_PATH")
EOF
chmod 0600 "$AZURE_ENV_FILE"
echo "Wrote Terraform auth env: $AZURE_ENV_FILE"

cat <<EOF

Azure bootstrap complete.

Normal Terraform workflow:
  cd $ROOT_DIR
  source .env.azure
  ./scripts/lab.sh doctor
  ./scripts/lab.sh plan
  ./scripts/lab.sh apply

Logout proof:
  az logout
  source $AZURE_ENV_FILE
  ./scripts/lab.sh plan
EOF
