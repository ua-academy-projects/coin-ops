#!/usr/bin/env bash
set -euo pipefail

# ARM - Azure Resource Manager, controls resources in azure and authorization (rbac roles)
# equivalent to account id  in aws, a place where resources are created and billed to, can have multiple subscriptions in one azure account
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:?Set SUBSCRIPTION_ID before running.sh}"

echo "Setting active subscription..."
az account set --subscription "${SUBSCRIPTION_ID}"

echo "Registering reequired resource providers..."
az provider register --namespace "Microsoft.Storage"

# loop every 10 sec until each provider is registered
echo "Waiting for providers to register..."
while [ "$(az provider show --namespace "Microsoft.Storage" --query "registrationState" -o tsv)" != "Registered" ]; do
    echo "Microsoft.Storage registering, waiting 10s..."
    sleep 10
done
echo "Microsoft.Storage registered"


RESOURCE_GROUP="${RESOURCE_GROUP:-coinops-dev-rg}"
LOCATION="${LOCATION:-polandcentral}"

echo "Checking if Resource Group exists..."
if ! az group show --name "${RESOURCE_GROUP}"  &>/dev/null; then
    echo "Creating Resource Group: ${RESOURCE_GROUP}"
    az group create \
        --name "${RESOURCE_GROUP}" \
        --location "${LOCATION}"
    echo "Resource Group created"
else
    echo "Resource Group already exists, skipping"
fi

IDENTITY_NAME="${IDENTITY_NAME:-coinops-dev-identity}"

echo "Checking if User Assigned Identity exists..."
if ! az identity show \
    --name "${IDENTITY_NAME}" \
    --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
    echo "Creating User Assigned Identity: ${IDENTITY_NAME}"
    az identity create \
        --name "${IDENTITY_NAME}" \
        --resource-group "${RESOURCE_GROUP}"
    echo "User Assigned Identity created"
else
    echo "User Assigned Identity already exists, skipping"
fi

# get identity details regardless of whether it was just created or already existed
IDENTITY_CLIENT_ID=$(az identity show \
    --name "${IDENTITY_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "clientId" -o tsv)

IDENTITY_ID=$(az identity show \
    --name "${IDENTITY_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "id" -o tsv)


SP_NAME="${SP_NAME:-coinops-dev-sp}"

# create-for-rbac - create with a role assignment instead of assigning a role with a separate block
# rbac - role based access control
# query "[0].id" - get the id of first sp found from json output, returns empty string if not found
# -o tsv - tab separated values, converts json to plain text
# grep -q . - check if output is not empty, returns 0 if found, 1 if not found
echo "Checking if Service Principal exists..."
if ! az ad sp list --display-name "${SP_NAME}" --query "[0].id" -o tsv | grep -q .; then
    echo "Creating Service Principal: ${SP_NAME}"
    # scope - apply to whole subscription
    # years - number of years the credentials will be valid, default is 1 year
    SP_CREDENTIALS=$(az ad sp create-for-rbac \
        --name "${SP_NAME}" \
        --role Contributor \
        --scopes "/subscriptions/${SUBSCRIPTION_ID}" \
        --years 99)
    echo "Service Principal created"
else
    echo "Service Principal already exists, skipping"
fi

KEY_FILE="${KEY_FILE:-$HOME/.secrets/azure/sp-key.json}"

echo "Writing key file ..."
# check if key file exists
if [ ! -f "${KEY_FILE}" ]; then
    # create ~/.secrets/azure directory if it doesn't exist
    mkdir -p "$(dirname "${KEY_FILE}")"

    # check if SP_CREDENTIALS is set, if not, reset credentials to get new secret
    # -z - check if variable is empty, -n - check if variable is not empty
    # SP_CREDENTIALS is empty (:- default empty var) - SP already existed, reset credentials to get new secret
    # SP_CREDENTIALS does only have value if SP is not created and is being created
    if [ -z "${SP_CREDENTIALS:-}" ]; then
        echo "SP already existed, resetting credentials to get new secret..."
        SP_APP_ID=$(az ad sp list --display-name "${SP_NAME}" --query "[0].appId" -o tsv)   # get appId of existing SP
        TENANT_ID=$(az account show --query "tenantId" -o tsv)  # get tenant id (organization id of whole azure account that contains subscriptions, applications)
        NEW_SECRET=$(az ad app credential reset --id "${SP_APP_ID}" --years 99 --query "password" -o tsv)   # reset credentials and get new secret
        # build credentials
        SP_CREDENTIALS=$(jq -n \
            --arg clientId "${SP_APP_ID}" \
            --arg clientSecret "${NEW_SECRET}" \
            --arg tenantId "${TENANT_ID}" \
            '{"clientId": $clientId, "clientSecret": $clientSecret, "tenantId": $tenantId}')
    fi

    # jq - process json
    #  .clientId - jq reads clientId from SP_CREDENTIALS (created in create-for-rbac)
    echo "${SP_CREDENTIALS}" | jq \
    --arg sub "${SUBSCRIPTION_ID}" '{
        clientId: .clientId,
        clientSecret: .clientSecret,
        tenantId: .tenantId,
        subscriptionId: $sub
    }' > "${KEY_FILE}"
    echo "Key file saved to ${KEY_FILE}"
else 
    echo "Key file already exists, skipping"
fi

# azure bucket
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:-coinopsdevtfstate}"

echo "Checking if Storage Account exists..."
if ! az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${RESOURCE_GROUP}" &>/dev/null; then
    echo "Creating Storage Account: ${STORAGE_ACCOUNT}"
    # --sku - stock keeping unit, LRS - locally redundant storage, 3 copies of data in same region, same data center
    # it defines how many copies of you data Azure keeps and where
    az storage account create \
        --name "${STORAGE_ACCOUNT}" \
        --resource-group "${RESOURCE_GROUP}" \
        --location "${LOCATION}" \
        --sku Standard_LRS
    echo "Storage Account created"
else
    echo "Storage Account already exists, skipping"
fi

# a folder inside storage account where tfstate files are stored (coinopsdevtfstate/tfstate)
CONTAINER_NAME="${CONTAINER_NAME:-tfstate}"

echo "Checking if Blob Container exists..."
if ! az storage container show \
    --name "${CONTAINER_NAME}" \
    --account-name "${STORAGE_ACCOUNT}" \
    --auth-mode login &>/dev/null; then
    echo "Creating Container: ${CONTAINER_NAME}"
    # --acount-name - storage account name (bucket)
    # --auth-mode login  - use az login credentials for authentication
    az storage container create \
        --name "${CONTAINER_NAME}" \
        --account-name "${STORAGE_ACCOUNT}" \
        --auth-mode login
    echo "Container created"
else
    echo "Container already exists, skipping"
fi

ENV_FILE="${ENV_FILE:-.env}"

echo "Writing environment variables to ${ENV_FILE}..."
# check if AZURE_AUTH_LOCATION is already set in .env, if so, replace it, if not, add it
if grep -q "AZURE_AUTH_LOCATION" "${ENV_FILE}" 2>/dev/null; then
      # sed - edit file in place -i - replace line that starts with export AZURE_AUTH_LOCATION= with new value, | is used as delimiter instead of / to avoid escaping
    sed -i '' "s|export AZURE_AUTH_LOCATION=.*|export AZURE_AUTH_LOCATION=${KEY_FILE}|" "${ENV_FILE}"
else
    echo "export AZURE_AUTH_LOCATION=${KEY_FILE}" >> "${ENV_FILE}"
fi

# write identity client id to .env
if grep -q "AZURE_IDENTITY_CLIENT_ID" "${ENV_FILE}" 2>/dev/null; then
    sed -i '' "s|export AZURE_IDENTITY_CLIENT_ID=.*|export AZURE_IDENTITY_CLIENT_ID=${IDENTITY_CLIENT_ID}|" "${ENV_FILE}"
else
    echo "export AZURE_IDENTITY_CLIENT_ID=${IDENTITY_CLIENT_ID}" >> "${ENV_FILE}"
fi

# write identity resource id to .env
if grep -q "AZURE_IDENTITY_ID" "${ENV_FILE}" 2>/dev/null; then
    sed -i '' "s|export AZURE_IDENTITY_ID=.*|export AZURE_IDENTITY_ID=${IDENTITY_ID}|" "${ENV_FILE}"
else
    echo "export AZURE_IDENTITY_ID=${IDENTITY_ID}" >> "${ENV_FILE}"
fi

echo "Done"

