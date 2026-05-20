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
#   9) Create a credentials file
#
# Usage:
#   1. Fill in the variables block below
#   2. chmod +x azure-bootstrap.sh
#   3. az login
#   4. ./azure-bootstrap.sh
#   5. Open Azure Portal and replace placeholder secret values

set -euo pipefail
# -e -> exit on error
# -u -> exit on unset variable
# -o pipefail -> exit on pipe failure

# ------------------------------------------------------------
# Variables
# ------------------------------------------------------------
AZ_GROUP_NAME="coin-ops-rg"
AZ_GROUP_LOCATION="austriaeast"

AZ_SP_NAME="coin-ops-sp"

AZ_STORAGE_ACCOUNT_NAME="coinopstfstate"
AZ_CONTAINER_NAME="tfstate"

AZ_KEYVAULT_NAME="coin-ops-keyvault-98123"
SECRET_PLACEHOLDER_VALUE="CHANGE_ME_IN_AZURE_PORTAL"
REQUIRED_SECRETS=(
  "ghcr-username"
  "ghcr-token"
  "rabbitmq-password"
  "db-password"
)

# ------------------------------------------------------------
# Validate required variables
# ------------------------------------------------------------
for var in \
  AZ_GROUP_NAME \
  AZ_GROUP_LOCATION \
  AZ_SP_NAME \
  AZ_STORAGE_ACCOUNT_NAME \
  AZ_CONTAINER_NAME \
  AZ_KEYVAULT_NAME \
  SECRET_PLACEHOLDER_VALUE; do
  if [[ -z "${!var}" ]]; then
    echo "ERROR: $var is not set. Fill in the variables block before running."
    exit 1
  fi
done

if [[ ${#REQUIRED_SECRETS[@]} -eq 0 ]]; then
  echo "ERROR: REQUIRED_SECRETS is empty. Add at least one secret name."
  exit 1
fi

# ------------------------------------------------------------
# Check required tools
# ------------------------------------------------------------
command -v az &>/dev/null && echo "Azure CLI is installed!" || { echo "Azure CLI is NOT installed!"; exit 1; }
command -v jq &>/dev/null && echo "jq is installed!"        || { echo "jq is NOT installed!";        exit 1; }

# ------------------------------------------------------------
# Get subscription ID
# ------------------------------------------------------------
AZ_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
echo "Using subscription: $AZ_SUBSCRIPTION_ID"

# ------------------------------------------------------------
# 1) Create a resource group
# ------------------------------------------------------------
echo ""
echo "==> Step 1: Resource Group"
if [[ $(az group exists --name ${AZ_GROUP_NAME}) == "true" ]]; then
  echo "Resource Group already exists: $AZ_GROUP_NAME"
else
  az group create --name ${AZ_GROUP_NAME} --location ${AZ_GROUP_LOCATION}
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
AZ_TENANT_ID=""

SP_APP_ID=$(az ad sp list --display-name ${AZ_SP_NAME} --query "[0].appId" --output tsv)

if [[ -z "$SP_APP_ID" ]]; then
  SP_OUTPUT=$(az ad sp create-for-rbac \
    --name $AZ_SP_NAME \
    --role Contributor \
    --scopes /subscriptions/$AZ_SUBSCRIPTION_ID/resourceGroups/$AZ_GROUP_NAME)

  AZ_CLIENT_ID=$(echo $SP_OUTPUT | jq -r '.appId')
  AZ_CLIENT_SECRET=$(echo $SP_OUTPUT | jq -r '.password')
  AZ_TENANT_ID=$(echo $SP_OUTPUT | jq -r '.tenant')

  echo "Service Principal created: $AZ_SP_NAME"
else
  echo "WARNING: Service Principal already exists: $AZ_SP_NAME"
  echo "WARNING: Client secret cannot be retrieved. Credentials file will be incomplete."
  echo "WARNING: Run 'az ad sp credential reset --name $AZ_SP_NAME' to generate a new secret."

  AZ_CLIENT_ID=$SP_APP_ID
  AZ_TENANT_ID=$(az account show --query tenantId --output tsv)
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
# 6) Register storage provider 
# ------------------------------------------------------------
echo ""
echo "==> Step 6: Register Storage Resource Provider"
az provider register --namespace Microsoft.Storage
echo "Microsoft.Storage provider registered"

# ------------------------------------------------------------
# 7) Create backend storage
# ------------------------------------------------------------
echo ""
echo "==> Step 7: Storage Account & Blob Container"

if az storage account show --name $AZ_STORAGE_ACCOUNT_NAME --resource-group $AZ_GROUP_NAME &>/dev/null; then
  echo "Storage Account already exists: $AZ_STORAGE_ACCOUNT_NAME"
else
  az storage account create \
    --name $AZ_STORAGE_ACCOUNT_NAME \
    --resource-group $AZ_GROUP_NAME \
    --location $AZ_GROUP_LOCATION \
    --sku Standard_LRS
  echo "Storage Account created: $AZ_STORAGE_ACCOUNT_NAME"
fi

if az storage container show \
  --name $AZ_CONTAINER_NAME \
  --account-name $AZ_STORAGE_ACCOUNT_NAME \
  --auth-mode login &>/dev/null; then
  echo "Blob Container already exists: $AZ_CONTAINER_NAME"
else
  az storage container create \
    --name $AZ_CONTAINER_NAME \
    --account-name $AZ_STORAGE_ACCOUNT_NAME \
    --auth-mode login
  echo "Blob Container created: $AZ_CONTAINER_NAME"
fi

# ------------------------------------------------------------
# 8) Assign storage blob role to service principal 
# ------------------------------------------------------------
echo ""
echo "==> Step 8: Storage Blob Role"
AZ_STORAGE_ID=$(az storage account show \
  --name $AZ_STORAGE_ACCOUNT_NAME \
  --resource-group $AZ_GROUP_NAME \
  --query id --output tsv)

az role assignment create \
  --assignee $AZ_CLIENT_ID \
  --role "Storage Blob Data Contributor" \
  --scope $AZ_STORAGE_ID
echo "Role assigned: Storage Blob Data Contributor"

# ------------------------------------------------------------
# 9) Create credentials file
# ------------------------------------------------------------
echo ""
echo "==> Step 9: Credentials File"

CREDENTIALS_FILE=".env"

cat > $CREDENTIALS_FILE <<EOF
ARM_SUBSCRIPTION_ID=$AZ_SUBSCRIPTION_ID
ARM_TENANT_ID=$AZ_TENANT_ID
ARM_CLIENT_ID=$AZ_CLIENT_ID
ARM_CLIENT_SECRET=$AZ_CLIENT_SECRET
TF_BACKEND_RESOURCE_GROUP=$AZ_GROUP_NAME
TF_BACKEND_STORAGE_ACCOUNT=$AZ_STORAGE_ACCOUNT_NAME
TF_BACKEND_CONTAINER=$AZ_CONTAINER_NAME
AZ_KEYVAULT_NAME=$AZ_KEYVAULT_NAME
EOF

echo "Credentials file created: $CREDENTIALS_FILE"
printf "\nDone!\n"
printf "  %-20s %s\n" "Resource group:" "$AZ_GROUP_NAME"
printf "  %-20s %s\n" "Key Vault:"      "$AZ_KEYVAULT_NAME"
printf "  %-20s %s\n" "Service principal:" "$AZ_SP_NAME"
printf "  %-20s %s\n" "State storage:"  "$AZ_STORAGE_ACCOUNT_NAME/$AZ_CONTAINER_NAME"
printf "  %-20s %s\n" "Env file:"       "$CREDENTIALS_FILE"
printf "\nNext steps:\n"
printf "  update placeholder secrets in Azure Key Vault\n"
printf "  source %s\n" "$CREDENTIALS_FILE"
printf "  terraform init\n"
printf "\nIMPORTANT: Add %s to your .gitignore because it contains secrets.\n" "$CREDENTIALS_FILE"
