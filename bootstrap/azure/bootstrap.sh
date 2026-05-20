#!/bin/bash
set -e

# === Configuration ===
# SUBSCRIPTION_ID    — Azure Free account (new, no policy restrictions)
# LOCATION           — infra region for VMs, PostgreSQL, NSG, VNet
# STATE_RG           — resource group for Terraform state storage ONLY
#                      created by bootstrap, NOT by Terraform
# INFRA_RG           — resource group for all infrastructure (VMs, VNet, etc.)
#                      created by Terraform in azure_network module, NOT by bootstrap
# WHY TWO RGs:
#   Bootstrap must create storage account before Terraform runs.
#   Storage account needs a resource group.
#   But infra resource group should be managed by Terraform (mentor requirement).
#   Solution: separate RG for state storage vs infra.
SUBSCRIPTION_ID="309b8392-8f83-4550-a1f2-678f169cc01b"
LOCATION="swedencentral"
STATE_RG="coinops-tfstate-rg"     # bootstrap creates this — for storage only
INFRA_RG="coinops-rg"             # Terraform creates this — for VMs, VNet, NSG, DB
STORAGE_ACCOUNT="coinopsmpenina"
CONTAINER_NAME="tfstate"
SP_NAME="terraform-sa"

# === Step 1: Set subscription ===
echo "Setting subscription..."
az account set --subscription $SUBSCRIPTION_ID
echo "Subscription set: $SUBSCRIPTION_ID"

# === Step 2: Register required resource providers ===
# Azure requires explicit registration of services before using them.
# Equivalent to: gcloud services enable in GCP.
# We register only what we actually use — least privilege principle.
echo "Registering resource providers..."
az provider register --namespace Microsoft.Storage --subscription $SUBSCRIPTION_ID
az provider register --namespace Microsoft.Compute --subscription $SUBSCRIPTION_ID
az provider register --namespace Microsoft.Network --subscription $SUBSCRIPTION_ID
az provider register --namespace Microsoft.DBforPostgreSQL --subscription $SUBSCRIPTION_ID

echo "Waiting for providers to register..."
for provider in Microsoft.Storage Microsoft.Compute Microsoft.Network Microsoft.DBforPostgreSQL; do
  while [ "$(az provider show --namespace $provider --query registrationState -o tsv)" != "Registered" ]; do
    echo "  Waiting for $provider..."
    sleep 10
  done
  echo "  $provider registered ✓"
done
echo "All providers registered."

# === Step 3: Create Resource Group for Terraform state storage ===
# WHY: Storage account must live in a resource group.
# This RG is ONLY for state storage — Terraform does NOT manage it.
# Infra RG (coinops-rg) is created separately by Terraform in azure_network module.
echo "Creating state storage resource group: $STATE_RG..."
if az group show --name $STATE_RG > /dev/null 2>&1; then
  echo "Resource group already exists, skipping."
else
  az group create \
    --name $STATE_RG \
    --location $LOCATION
  echo "Resource group created."
fi

# === Step 4: Create Storage Account for Terraform state ===
# WHY: Terraform state must be stored remotely so that:
# - team members share the same state
# - state survives local machine loss
# - CI/CD pipelines can access it
echo "Creating storage account: $STORAGE_ACCOUNT in $STATE_RG..."
if az storage account show \
    --name $STORAGE_ACCOUNT \
    --resource-group $STATE_RG \
    --subscription $SUBSCRIPTION_ID > /dev/null 2>&1; then
  echo "Storage account already exists, skipping."
else
  az storage account create \
    --name $STORAGE_ACCOUNT \
    --resource-group $STATE_RG \
    --location $LOCATION \
    --subscription $SUBSCRIPTION_ID \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false
  echo "Storage account created."
  echo "Waiting for storage account to be ready..."
  sleep 15
fi

# === Step 5: Enable versioning on storage account ===
# WHY: Versioning keeps history of state file changes.
# If Terraform corrupts state, you can restore a previous version.
echo "Enabling blob versioning..."
az storage account blob-service-properties update \
  --account-name $STORAGE_ACCOUNT \
  --resource-group $STATE_RG \
  --enable-versioning true 2>/dev/null \
  || echo "Versioning not available in this region, skipping."
echo "Versioning step complete."

# === Step 6: Create Blob Container ===
# WHY: Container is the folder inside storage account where state file lives.
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

# === Step 7: Create Service Principal for Terraform ===
# WHY: Terraform needs credentials to create Azure resources.
# Service Principal = non-human robot account with specific permissions.
# We use client_secret auth — standard approach for local development.
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
  echo "azure_subscription_id = \"$SUBSCRIPTION_ID\""
  echo "azure_client_id       = \"$CLIENT_ID\""
  echo "azure_client_secret   = \"HIDDEN - save from your terminal\""
  echo "azure_tenant_id       = \"$TENANT_ID\""
fi

# === Step 8: Assign roles to Service Principal ===
# Contributor         — create/modify/delete Azure resources (VMs, VNet, NSG, DB)
# Reader              — read subscription metadata and provider list on startup
#                       Theoretically in Contributor but sometimes blocked explicitly
# Storage Blob Data Contributor — read/write state file in Blob storage
#                       Without this Terraform cannot save state even with Contributor
echo "Assigning roles to service principal..."
SP_OBJECT_ID=$(az ad sp show \
  --id $(az ad sp list --display-name $SP_NAME --query "[0].appId" -o tsv) \
  --query id -o tsv)

STORAGE_ACCOUNT_ID=$(az storage account show \
  --name $STORAGE_ACCOUNT \
  --resource-group $STATE_RG \
  --query id -o tsv)

MSYS_NO_PATHCONV=1 az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Reader" \
  --scope /subscriptions/$SUBSCRIPTION_ID 2>/dev/null \
  || echo "Reader role already assigned, skipping."

MSYS_NO_PATHCONV=1 az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" \
  --scope "$STORAGE_ACCOUNT_ID" 2>/dev/null \
  || echo "Storage Blob Data Contributor already assigned, skipping."

echo "Roles assigned."

echo ""
echo "=== Bootstrap complete ==="
echo "Subscription ID:  $SUBSCRIPTION_ID"
echo "State RG:         $STATE_RG  (bootstrap manages — storage only)"
echo "Infra RG:         $INFRA_RG  (Terraform manages — VMs, VNet, NSG, DB)"
echo "Storage Account:  $STORAGE_ACCOUNT"
echo "Container:        $CONTAINER_NAME"
echo "Location:         $LOCATION"
echo ""
echo "Next steps:"
echo "  1. Save credentials shown above to terraform/terraform.tfvars"
echo "  2. Update backend.tf: resource_group_name = \"$STATE_RG\""
echo "  3. Ensure config.yaml: general.cloud: \"azure\", region: \"swedencentral\""
echo "  4. Run: cd terraform && terraform init"
echo "  5. Run: terraform apply"