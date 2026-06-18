#!/usr/bin/env bash
# Azure Bootstrap Script
# Purpose: Prepare a project for infrastructure provisioning
# Steps:
#   1) Create a resource group
#   2) Create a key vault
#   3) Create a service principal
#   4) Assign Key Vault access to the active Azure CLI caller
#   5) Create required secret entries with placeholder values
#   6) Register the storage resource provider
#   7) Create backend storage for Terraform state
#   8) Assign storage blob access to the service principal
#   9) Create backend config and credentials files
#
# Usage:
#   1. Optionally override variables with environment values
#   2. chmod +x azure-bootstrap.sh
#   3. az login
#   4. ./azure-bootstrap.sh
#   5. Open Azure Portal and replace placeholder secret values
#   6. Run: terraform init -backend-config=backend.azure.hcl

set -euo pipefail
# -e -> exit on error
# -u -> exit on unset variable
# -o pipefail -> exit on pipe failure

# ------------------------------------------------------------
# Defaults
# ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

AZ_GROUP_NAME="${AZ_GROUP_NAME:-coin-ops-rg}"
AZ_GROUP_LOCATION="${AZ_GROUP_LOCATION:-austriaeast}"

AZ_SP_NAME="${AZ_SP_NAME:-coin-ops-sp}"

CREATE_BACKEND="${CREATE_BACKEND:-true}"
AZ_STORAGE_ACCOUNT_NAME="${AZ_STORAGE_ACCOUNT_NAME:-}"
AZ_CONTAINER_NAME="${AZ_CONTAINER_NAME:-tfstate}"
BACKEND_CONFIG_FILE="${BACKEND_CONFIG_FILE:-$SCRIPT_DIR/backend.azure.hcl}"

AZ_KEYVAULT_NAME="${AZ_KEYVAULT_NAME:-}"
CREDENTIALS_FILE="${CREDENTIALS_FILE:-$SCRIPT_DIR/azure.env}"
TERRAFORM_VARS_FILE="${TERRAFORM_VARS_FILE:-$REPO_ROOT/terraform/cloud/azure.auto.tfvars.json}"
TF_CONFIG_NAME="${TF_CONFIG_NAME:-test}"
SECRET_PLACEHOLDER_VALUE="${SECRET_PLACEHOLDER_VALUE:-CHANGE_ME_IN_AZURE_PORTAL}"
REQUIRED_SECRETS=(
  "ghcr-username"
  "ghcr-token"
  "rabbitmq-password"
  "db-password"
)

REQUIRED_RESOURCE_PROVIDERS=(
  "Microsoft.KeyVault"
  "Microsoft.Storage"
)

PROVIDER_REGISTRATION_MAX_ATTEMPTS="${PROVIDER_REGISTRATION_MAX_ATTEMPTS:-12}"
PROVIDER_REGISTRATION_SLEEP_SECONDS="${PROVIDER_REGISTRATION_SLEEP_SECONDS:-10}"

# ------------------------------------------------------------
# Validate required variables
# ------------------------------------------------------------
for var in \
  AZ_GROUP_NAME \
  AZ_GROUP_LOCATION \
  AZ_SP_NAME \
  CREATE_BACKEND \
  AZ_CONTAINER_NAME \
  BACKEND_CONFIG_FILE \
  CREDENTIALS_FILE \
  TERRAFORM_VARS_FILE \
  TF_CONFIG_NAME \
  SECRET_PLACEHOLDER_VALUE; do
  if [[ -z "${!var}" ]]; then
    echo "ERROR: $var is not set. Fill in the variables block before running."
    exit 1
  fi
done

if [[ "$CREATE_BACKEND" != "true" && "$CREATE_BACKEND" != "false" ]]; then
  echo "ERROR: CREATE_BACKEND must be either 'true' or 'false'."
  exit 1
fi

if ! [[ "$PROVIDER_REGISTRATION_MAX_ATTEMPTS" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: PROVIDER_REGISTRATION_MAX_ATTEMPTS must be a positive integer."
  exit 1
fi

if ! [[ "$PROVIDER_REGISTRATION_SLEEP_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "ERROR: PROVIDER_REGISTRATION_SLEEP_SECONDS must be a positive integer."
  exit 1
fi

if [[ ${#REQUIRED_SECRETS[@]} -eq 0 ]]; then
  echo "ERROR: REQUIRED_SECRETS is empty. Add at least one secret name."
  exit 1
fi

if [[ ${#REQUIRED_RESOURCE_PROVIDERS[@]} -eq 0 ]]; then
  echo "ERROR: REQUIRED_RESOURCE_PROVIDERS is empty. Add at least one provider namespace."
  exit 1
fi

# ------------------------------------------------------------
# Check required tools
# ------------------------------------------------------------
for tool in az jq terraform; do
  if command -v "$tool" &>/dev/null; then
    echo "$tool is installed."
  else
    echo "ERROR: $tool is not installed or not available on PATH."
    exit 1
  fi
done

# ------------------------------------------------------------
# Validate Azure authentication
# ------------------------------------------------------------
if ! az account show &>/dev/null; then
  echo "ERROR: Azure CLI is not authenticated. Run 'az login' first."
  exit 1
fi

AZ_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
AZ_TENANT_ID=$(az account show --query tenantId --output tsv)
echo "Using subscription: $AZ_SUBSCRIPTION_ID"
echo "Using tenant: $AZ_TENANT_ID"

if [[ -z "$AZ_KEYVAULT_NAME" ]]; then
  AZ_KEYVAULT_SUFFIX=$(echo "$AZ_SUBSCRIPTION_ID" | tr -d '-' | cut -c1-10)
  AZ_KEYVAULT_NAME="coinopskv${AZ_KEYVAULT_SUFFIX}"
fi

if [[ -z "$AZ_STORAGE_ACCOUNT_NAME" ]]; then
  AZ_STORAGE_SUFFIX=$(echo "$AZ_SUBSCRIPTION_ID" | tr -d '-' | cut -c1-10)
  AZ_STORAGE_ACCOUNT_NAME="coinopstf${AZ_STORAGE_SUFFIX}"
fi

if ! [[ "$AZ_KEYVAULT_NAME" =~ ^[a-zA-Z][a-zA-Z0-9-]{1,22}[a-zA-Z0-9]$ ]]; then
  echo "ERROR: AZ_KEYVAULT_NAME must be 3-24 characters, start with a letter, end with a letter or number, and contain only letters, numbers, and hyphens."
  exit 1
fi

if ! [[ "$AZ_STORAGE_ACCOUNT_NAME" =~ ^[a-z0-9]{3,24}$ ]]; then
  echo "ERROR: AZ_STORAGE_ACCOUNT_NAME must be 3-24 characters and contain only lowercase letters and numbers."
  exit 1
fi

echo "Using Key Vault name: $AZ_KEYVAULT_NAME"
echo "Using storage account name: $AZ_STORAGE_ACCOUNT_NAME"

# ------------------------------------------------------------
# Register required resource providers
# ------------------------------------------------------------
wait_for_provider_registration() {
  local namespace="$1"
  local state=""

  echo "Registering resource provider: $namespace"
  az provider register --namespace "$namespace" --output none

  for ((attempt = 1; attempt <= PROVIDER_REGISTRATION_MAX_ATTEMPTS; attempt++)); do
    state=$(az provider show \
      --namespace "$namespace" \
      --query registrationState \
      --output tsv)

    if [[ "$state" == "Registered" ]]; then
      echo "Resource provider registered: $namespace"
      return 0
    fi

    echo "Resource provider $namespace is $state; waiting ${PROVIDER_REGISTRATION_SLEEP_SECONDS}s (${attempt}/${PROVIDER_REGISTRATION_MAX_ATTEMPTS})"
    sleep "$PROVIDER_REGISTRATION_SLEEP_SECONDS"
  done

  echo "ERROR: Resource provider $namespace did not become Registered."
  echo "ERROR: Last state: $state"
  exit 1
}

echo ""
echo "==> Resource Providers"
for namespace in "${REQUIRED_RESOURCE_PROVIDERS[@]}"; do
  wait_for_provider_registration "$namespace"
done

# ------------------------------------------------------------
# 1) Create a resource group
# ------------------------------------------------------------
echo ""
echo "==> Step 1: Resource Group"
if [[ $(az group exists --name "$AZ_GROUP_NAME") == "true" ]]; then
  echo "Resource Group already exists: $AZ_GROUP_NAME"
else
  az group create --name "$AZ_GROUP_NAME" --location "$AZ_GROUP_LOCATION"
  echo "Resource Group created: $AZ_GROUP_NAME"
fi

# ------------------------------------------------------------
# 2) Create a key vault
# ------------------------------------------------------------
echo ""
echo "==> Step 2: Key Vault"

if az keyvault show --name "$AZ_KEYVAULT_NAME" --resource-group "$AZ_GROUP_NAME" &>/dev/null; then
  echo "Key Vault already exists: $AZ_KEYVAULT_NAME"
else
  az keyvault create \
    --name "$AZ_KEYVAULT_NAME" \
    --resource-group "$AZ_GROUP_NAME" \
    --location "$AZ_GROUP_LOCATION"

  echo "Key Vault created: $AZ_KEYVAULT_NAME"
fi

# ------------------------------------------------------------
# 3) Create a service principal
# ------------------------------------------------------------
echo ""
echo "==> Step 3: Service Principal"

AZ_CLIENT_ID=""
AZ_CLIENT_SECRET=""

SP_APP_ID=$(az ad sp list --display-name "$AZ_SP_NAME" --query "[0].appId" --output tsv)

if [[ -z "$SP_APP_ID" ]]; then
  SP_OUTPUT=$(az ad sp create-for-rbac \
    --name "$AZ_SP_NAME" \
    --role Contributor \
    --scopes "/subscriptions/$AZ_SUBSCRIPTION_ID/resourceGroups/$AZ_GROUP_NAME")

  AZ_CLIENT_ID=$(echo "$SP_OUTPUT" | jq -r '.appId')
  AZ_CLIENT_SECRET=$(echo "$SP_OUTPUT" | jq -r '.password')
  AZ_TENANT_ID=$(echo "$SP_OUTPUT" | jq -r '.tenant')

  echo "Service Principal created: $AZ_SP_NAME"
else
  echo "Service Principal already exists: $AZ_SP_NAME"
  echo "Resetting service principal credential so Terraform env file is complete."

  SP_OUTPUT=$(az ad sp credential reset \
    --id "$SP_APP_ID" \
    --query "{appId:appId,password:password,tenant:tenant}" \
    --output json)

  AZ_CLIENT_ID=$(echo "$SP_OUTPUT" | jq -r '.appId')
  AZ_CLIENT_SECRET=$(echo "$SP_OUTPUT" | jq -r '.password')
  AZ_TENANT_ID=$(echo "$SP_OUTPUT" | jq -r '.tenant')

  echo "Service Principal credential reset: $AZ_SP_NAME"
fi

# ------------------------------------------------------------
# 4) Assign a key vault role to the active azure cli caller
# ------------------------------------------------------------
echo ""
echo "==> Step 4: Key Vault RBAC"

AZ_KEYVAULT_ID=$(az keyvault show \
  --name "$AZ_KEYVAULT_NAME" \
  --resource-group "$AZ_GROUP_NAME" \
  --query id --output tsv)

AZ_CALLER_OBJECT_ID=$(az ad signed-in-user show --query id --output tsv)

az role assignment create \
  --assignee-object-id "$AZ_CALLER_OBJECT_ID" \
  --assignee-principal-type User \
  --role "Key Vault Secrets Officer" \
  --scope "$AZ_KEYVAULT_ID" &>/dev/null || true

echo "Waiting for Key Vault RBAC propagation..."
sleep 30

echo "Key Vault Secrets Officer role ensured for the active Azure CLI caller"


# ------------------------------------------------------------
# 5) Create required secret entries
# ------------------------------------------------------------
echo ""
echo "==> Step 5: Key Vault Secrets"

for secret_name in "${REQUIRED_SECRETS[@]}"; do
  if az keyvault secret show \
    --vault-name "$AZ_KEYVAULT_NAME" \
    --name "$secret_name" &>/dev/null; then
    echo "Secret already exists: $secret_name"
  else
    az keyvault secret set \
      --vault-name "$AZ_KEYVAULT_NAME" \
      --name "$secret_name" \
      --value "$SECRET_PLACEHOLDER_VALUE" \
      --output none

    echo "Secret created with placeholder value: $secret_name"
  fi
done

echo ""
echo "WARNING: Required secrets now exist in Key Vault, but may still contain the bootstrap placeholder."
echo "WARNING: Open Azure Portal and replace placeholder values for:"
for secret_name in "${REQUIRED_SECRETS[@]}"; do
  echo " - $secret_name"
done

# ------------------------------------------------------------
# 7) Create backend storage
# ------------------------------------------------------------
echo ""
echo "==> Step 7: Storage Account & Blob Container"

if [[ "$CREATE_BACKEND" == "true" ]]; then
  if az storage account show --name "$AZ_STORAGE_ACCOUNT_NAME" --resource-group "$AZ_GROUP_NAME" &>/dev/null; then
    echo "Storage Account already exists: $AZ_STORAGE_ACCOUNT_NAME"
  else
    az storage account create \
      --name "$AZ_STORAGE_ACCOUNT_NAME" \
      --resource-group "$AZ_GROUP_NAME" \
      --location "$AZ_GROUP_LOCATION" \
      --sku Standard_LRS
    echo "Storage Account created: $AZ_STORAGE_ACCOUNT_NAME"
  fi

  if az storage container show \
    --name "$AZ_CONTAINER_NAME" \
    --account-name "$AZ_STORAGE_ACCOUNT_NAME" \
    --auth-mode login &>/dev/null; then
    echo "Blob Container already exists: $AZ_CONTAINER_NAME"
  else
    az storage container create \
      --name "$AZ_CONTAINER_NAME" \
      --account-name "$AZ_STORAGE_ACCOUNT_NAME" \
      --auth-mode login
    echo "Blob Container created: $AZ_CONTAINER_NAME"
  fi

  cat > "$BACKEND_CONFIG_FILE" <<EOF
resource_group_name  = "$AZ_GROUP_NAME"
storage_account_name = "$AZ_STORAGE_ACCOUNT_NAME"
container_name       = "$AZ_CONTAINER_NAME"
key                  = "cloud/terraform.tfstate"
EOF
  chmod 600 "$BACKEND_CONFIG_FILE"
else
  echo "CREATE_BACKEND is false, skipping Azure storage backend"
fi

# ------------------------------------------------------------
# 8) Assign storage blob role to service principal 
# ------------------------------------------------------------
echo ""
echo "==> Step 8: Storage Blob Role"
if [[ "$CREATE_BACKEND" == "true" ]]; then
  AZ_STORAGE_ID=$(az storage account show \
    --name "$AZ_STORAGE_ACCOUNT_NAME" \
    --resource-group "$AZ_GROUP_NAME" \
    --query id --output tsv)

  az role assignment create \
    --assignee "$AZ_CLIENT_ID" \
    --role "Storage Blob Data Contributor" \
    --scope "$AZ_STORAGE_ID"
  echo "Role assigned: Storage Blob Data Contributor"
else
  echo "CREATE_BACKEND is false, skipping storage role assignment"
fi

# ------------------------------------------------------------
# 9) Create credentials file
# ------------------------------------------------------------
echo ""
echo "==> Step 9: Credentials File"

cat > "$CREDENTIALS_FILE" <<EOF
ARM_SUBSCRIPTION_ID=$AZ_SUBSCRIPTION_ID
ARM_TENANT_ID=$AZ_TENANT_ID
ARM_CLIENT_ID=$AZ_CLIENT_ID
ARM_CLIENT_SECRET=$AZ_CLIENT_SECRET
TF_BACKEND_RESOURCE_GROUP=$AZ_GROUP_NAME
TF_BACKEND_STORAGE_ACCOUNT=$AZ_STORAGE_ACCOUNT_NAME
TF_BACKEND_CONTAINER=$AZ_CONTAINER_NAME
TF_CREATE_BACKEND=$CREATE_BACKEND
AZ_KEYVAULT_NAME=$AZ_KEYVAULT_NAME
EOF
chmod 600 "$CREDENTIALS_FILE"

echo "Credentials file created: $CREDENTIALS_FILE"

# ------------------------------------------------------------
# 10) Create Terraform variables file
# ------------------------------------------------------------
echo ""
echo "==> Step 10: Terraform Variables File"

mkdir -p "$(dirname "$TERRAFORM_VARS_FILE")"
cat > "$TERRAFORM_VARS_FILE" <<EOF
{
  "config_name": "$TF_CONFIG_NAME",
  "azure_resource_group_name": "$AZ_GROUP_NAME",
  "azure_key_vault_name": "$AZ_KEYVAULT_NAME",
  "azure_location": "$AZ_GROUP_LOCATION"
}
EOF
chmod 600 "$TERRAFORM_VARS_FILE"

echo "Terraform variables file created: $TERRAFORM_VARS_FILE"

printf "\nDone!\n"
printf "  %-20s %s\n" "Resource group:" "$AZ_GROUP_NAME"
printf "  %-20s %s\n" "Key Vault:"      "$AZ_KEYVAULT_NAME"
printf "  %-20s %s\n" "Service principal:" "$AZ_SP_NAME"
printf "  %-20s %s\n" "State storage:"  "$([[ "$CREATE_BACKEND" == "true" ]] && echo "$AZ_STORAGE_ACCOUNT_NAME/$AZ_CONTAINER_NAME" || echo "skipped")"
printf "  %-20s %s\n" "Backend config:" "$([[ "$CREATE_BACKEND" == "true" ]] && echo "$BACKEND_CONFIG_FILE" || echo "skipped")"
printf "  %-20s %s\n" "Env file:"       "$CREDENTIALS_FILE"
printf "  %-20s %s\n" "Terraform vars:" "$TERRAFORM_VARS_FILE"
printf "\nNext steps:\n"
printf "  update placeholder secrets in Azure Key Vault\n"
printf "  source %s\n" "$CREDENTIALS_FILE"
printf "  terraform -chdir=terraform/cloud init -backend-config=%s -reconfigure\n" "$BACKEND_CONFIG_FILE"
printf "  terraform -chdir=terraform/cloud plan -lock-timeout=30s\n"
printf "\nIMPORTANT: Keep %s and %s ignored because they contain local environment values.\n" "$CREDENTIALS_FILE" "$TERRAFORM_VARS_FILE"
