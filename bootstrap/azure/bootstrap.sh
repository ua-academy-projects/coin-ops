#!/bin/bash
set -e

SUBSCRIPTION_ID="387c88f6-124c-413f-936b-75b578dbabc9"
LOCATION="swedencentral"
SP_NAME="terraform-sa"

# Step 1: Set subscription
echo "Setting subscription..."
az account set --subscription $SUBSCRIPTION_ID

# Step 2: Register providers
echo "Registering resource providers..."
for provider in Microsoft.Storage Microsoft.Compute Microsoft.Network; do
  az provider register --namespace $provider --subscription $SUBSCRIPTION_ID
done

echo "Waiting for providers..."
for provider in Microsoft.Storage Microsoft.Compute Microsoft.Network; do
  while [ "$(az provider show --namespace $provider \
    --query registrationState -o tsv)" != "Registered" ]; do
    echo "  Waiting for $provider..."
    sleep 10
  done
  echo "  $provider registered ✓"
done

# Step 3: Create or reset Service Principal
echo "Creating/resetting service principal..."
SP_APP_ID=$(az ad sp list --display-name $SP_NAME \
  --query "[0].appId" -o tsv)

if echo "$SP_APP_ID" | grep -q .; then
  echo "SP exists — resetting credentials..."
  MSYS_NO_PATHCONV=1 az ad sp credential reset \
    --id "$SP_APP_ID" \
    --output json
else
  MSYS_NO_PATHCONV=1 az ad sp create-for-rbac \
    --name $SP_NAME \
    --role Contributor \
    --scopes /subscriptions/$SUBSCRIPTION_ID \
    --output json
fi

# Step 4: Assign Contributor role to new subscription
echo "Assigning Contributor role..."
SP_OBJECT_ID=$(az ad sp show \
  --id $(az ad sp list --display-name $SP_NAME \
  --query "[0].appId" -o tsv) \
  --query id -o tsv)

MSYS_NO_PATHCONV=1 az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" \
  --scope /subscriptions/$SUBSCRIPTION_ID 2>/dev/null \
  || echo "Contributor role already assigned."

MSYS_NO_PATHCONV=1 az role assignment create \
  --assignee-object-id "$SP_OBJECT_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Reader" \
  --scope /subscriptions/$SUBSCRIPTION_ID 2>/dev/null \
  || echo "Reader role already assigned."

echo ""
echo "=== Bootstrap complete ==="
echo "Save credentials above to terraform/terraform.tfvars"