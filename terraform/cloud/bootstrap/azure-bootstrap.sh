#!/bin/bash
# Azure Bootstrap Script
# Purpose: Prepare a project for infrastructure provisioning
# Steps:
#   1) Create a resource group
#   2) Create a service principal
#   3) Assign proper permissions to the service principal
#   4) Create a backend storage for Terraform state files
#   5) Create a credentials file
#   6) Prepare secrets
#
# Usage:
#   1. Fill in the variables block below
#   2. chmod +x azure-bootstrap.sh
#   3. az login
#   4. ./azure-bootstrap.sh

set -euo pipefail
# -e -> exit on error
# -u -> exit on unset variable
# -o pipefail -> exit on pipe failure

# ============================================================
# Variables — fill in before running
# ============================================================
AZ_GROUP_NAME="coin-ops-rg"
AZ_GROUP_LOCATION="westeurope"
AZ_SP_NAME="coin-ops-sp"
AZ_STORAGE_ACCOUNT_NAME="coinopstfstate"
AZ_CONTAINER_NAME="tfstate"

AZ_KEYVAULT_NAME="coin-ops-kv"

REQUIRED_SECRETS=(
  "ghrc-username"
  "ghrc-token"
  "rabbitmq-password"
  "db-password"
)

SECRET_PLACEHOLDER_VALUE="CHANGE_ME_IN_AZURE_PORTAL"
# ============================================================

# ------------------------------------------------------------
# Validate required variables
# ------------------------------------------------------------
for var in AZ_GROUP_NAME AZ_GROUP_LOCATION AZ_SP_NAME AZ_STORAGE_ACCOUNT_NAME AZ_CONTAINER_NAME; do
  if [[ -z "${!var}" ]]; then
    echo "ERROR: $var is not set. Fill in the variables block before running."
    exit 1
  fi
done

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
# 2) Create a service principal
# ------------------------------------------------------------
echo ""
echo "==> Step 2: Service Principal"

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
# 3) Register Storage provider + assign blob role (after storage created)
# ------------------------------------------------------------
echo ""
echo "==> Step 3: Register Storage Resource Provider"
az provider register --namespace Microsoft.Storage
echo "Microsoft.Storage provider registered"

# ------------------------------------------------------------
# 4) Create backend storage
# ------------------------------------------------------------
echo ""
echo "==> Step 4: Storage Account & Blob Container"

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

# Assign Storage Blob Data Contributor to the Service Principal
echo "Assigning Storage Blob Data Contributor role..."
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
# 5) Create credentials file
# ------------------------------------------------------------
echo ""
echo "==> Step 5: Credentials File"

CREDENTIALS_FILE=".env"

cat > $CREDENTIALS_FILE <<EOF
ARM_SUBSCRIPTION_ID=$AZ_SUBSCRIPTION_ID
ARM_TENANT_ID=$AZ_TENANT_ID
ARM_CLIENT_ID=$AZ_CLIENT_ID
ARM_CLIENT_SECRET=$AZ_CLIENT_SECRET
TF_BACKEND_RESOURCE_GROUP=$AZ_GROUP_NAME
TF_BACKEND_STORAGE_ACCOUNT=$AZ_STORAGE_ACCOUNT_NAME
TF_BACKEND_CONTAINER=$AZ_CONTAINER_NAME
EOF

echo "Credentials file created: $CREDENTIALS_FILE"
echo ""
echo "IMPORTANT: Add .env to your .gitignore — it contains secrets!"
echo ""
echo "==> Bootstrap complete!"
