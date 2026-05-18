#!/bin/bash
set -e

# === Configuration ===
# Region matches config.yaml locations.europe.azure.region
SUBSCRIPTION_ID="387c88f6-124c-413f-936b-75b578dbabc9"
LOCATION="germanywestcentral"
RESOURCE_GROUP="coinops-rg"
STORAGE_ACCOUNT="coinopspenina"
CONTAINER_NAME="tfstate"
SP_NAME="terraform-sa"

# === Step 1: Set subscription ===
echo "Setting subscription..."
az account set --subscription $SUBSCRIPTION_ID
echo "Subscription set: $SUBSCRIPTION_ID"

# === Step 1.5: Register required resource providers ===
echo "Registering resource providers..."
az provider register --namespace Microsoft.Storage --subscription $SUBSCRIPTION_ID
az provider register --namespace Microsoft.Compute --subscription $SUBSCRIPTION_ID
az provider register --namespace Microsoft.Network --subscription $SUBSCRIPTION_ID
az provider register --namespace Microsoft.Sql --subscription $SUBSCRIPTION_ID
az provider register --namespace Microsoft.DBforPostgreSQL --subscription $SUBSCRIPTION_ID

echo "Waiting for providers to register..."
for provider in Microsoft.Storage Microsoft.Compute Microsoft.Network Microsoft.Sql Microsoft.DBforPostgreSQL; do
  while [ "$(az provider show --namespace $provider --query registrationState -o tsv)" != "Registered" ]; do
    echo "  Waiting for $provider..."
    sleep 10
  done
  echo "  $provider registered ✓"
done
echo "All providers registered."

# === Step 2: Create Resource Group ===
echo "Creating resource group: $RESOURCE_GROUP..."
if az group show --name $RESOURCE_GROUP > /dev/null 2>&1; then
  echo "Resource group already exists, skipping."
else
  az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION
  echo "Resource group created."
fi

# === Step 3: Create Storage Account for Terraform state ===
echo "Creating storage account: $STORAGE_ACCOUNT..."
if az storage account show \
    --name $STORAGE_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --subscription $SUBSCRIPTION_ID > /dev/null 2>&1; then
  echo "Storage account already exists, skipping."
else
  az storage account create \
    --name $STORAGE_ACCOUNT \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --subscription $SUBSCRIPTION_ID \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false
  echo "Storage account created."
fi

# === Step 4: Enable versioning on storage account ===
echo "Enabling blob versioning..."
az storage account blob-service-properties update \
  --account-name $STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --enable-versioning true
echo "Versioning enabled."

# === Step 5: Create Blob Container ===
echo "Creating blob container: $CONTAINER_NAME..."
if az storage container show \
    --name $CONTAINER_NAME \
    --account-name $STORAGE_ACCOUNT \
    --auth-mode login > /dev/null 2>&1; then
  echo "Container already exists, skipping."
else
  az storage container create \
    --name $CONTAINER_NAME \
    --account-name $STORAGE_ACCOUNT \
    --auth-mode login
  echo "Container created."
fi

# === Step 6: Create Service Principal for Terraform ===
echo "Creating service principal: $SP_NAME..."
if az ad sp list --display-name $SP_NAME --query "[0].appId" -o tsv | grep -q .; then
  echo "Service principal already exists, skipping creation."
  CLIENT_ID=$(az ad sp list --display-name $SP_NAME --query "[0].appId" -o tsv)
  echo "Existing client ID: $CLIENT_ID"
  echo "Note: client_secret is not retrievable for existing SP."
  echo "If you need new credentials run:"
  echo "  az ad sp credential reset --name $SP_NAME"
else
  SP_OUTPUT=$(MSYS_NO_PATHCONV=1 az ad sp create-for-rbac \
    --name $SP_NAME \
    --role Contributor \
    --scopes /subscriptions/$SUBSCRIPTION_ID \
    --output json)

  CLIENT_ID=$(echo $SP_OUTPUT | grep -o '"appId":"[^"]*"' | cut -d'"' -f4)
  CLIENT_SECRET=$(echo $SP_OUTPUT | grep -o '"password":"[^"]*"' | cut -d'"' -f4)
  TENANT_ID=$(echo $SP_OUTPUT | grep -o '"tenant":"[^"]*"' | cut -d'"' -f4)

  echo ""
  echo "=== Credentials (save these securely, shown only once) ==="
  echo "azure_client_id       = \"$CLIENT_ID\""
  echo "azure_client_secret   = \"HIDDEN - save from your terminal\""
  echo "azure_tenant_id       = \"$TENANT_ID\""
fi

echo ""
echo "=== Bootstrap complete ==="
echo "Location:         $LOCATION   (matches config.yaml locations.europe.azure.region)"
echo "Subscription ID:  $SUBSCRIPTION_ID"
echo "Resource Group:   $RESOURCE_GROUP"
echo "Storage Account:  $STORAGE_ACCOUNT"
echo "Container:        $CONTAINER_NAME"
echo ""
echo "Next steps:"
echo "  1. Add credentials to terraform/terraform.tfvars"
echo "  2. Uncomment Azure backend in terraform/backend.tf"
echo "  3. Change config.yaml: general.cloud: \"azure\""
echo "  4. Run: terraform init"
echo "  5. Run: terraform apply"