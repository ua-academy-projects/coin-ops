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
#  10) Optionally create Azure DevOps service connection and pipeline
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
AZ_GROUP_NAME="${AZ_GROUP_NAME:-coin-ops-rg}"
AZ_GROUP_LOCATION="${AZ_GROUP_LOCATION:-austriaeast}"

AZ_SP_NAME="${AZ_SP_NAME:-coin-ops-sp}"

CREATE_BACKEND="${CREATE_BACKEND:-true}"
AZ_STORAGE_ACCOUNT_NAME="${AZ_STORAGE_ACCOUNT_NAME:-coinopstfstate}"
AZ_CONTAINER_NAME="${AZ_CONTAINER_NAME:-tfstate}"
BACKEND_CONFIG_FILE="${BACKEND_CONFIG_FILE:-./backend.azure.hcl}"

AZ_KEYVAULT_NAME="${AZ_KEYVAULT_NAME:-coin-ops-keyvault-98123}"
CREDENTIALS_FILE="${CREDENTIALS_FILE:-./terraform.env}"
SECRET_PLACEHOLDER_VALUE="${SECRET_PLACEHOLDER_VALUE:-CHANGE_ME_IN_AZURE_PORTAL}"
REQUIRED_SECRETS=(
  "ghcr-username"
  "ghcr-token"
  "rabbitmq-password"
  "db-password"
)

AZDO_CONFIGURE="${AZDO_CONFIGURE:-false}"
AZDO_CREATE_PIPELINE="${AZDO_CREATE_PIPELINE:-false}"
AZDO_ORG_URL="${AZDO_ORG_URL:-}"
AZDO_PROJECT="${AZDO_PROJECT:-}"
AZDO_PAT="${AZDO_PAT:-}"
AZDO_SERVICE_CONNECTION_NAME="${AZDO_SERVICE_CONNECTION_NAME:-coin-ops-terraform}"
AZDO_AUTHORIZE_SERVICE_CONNECTION="${AZDO_AUTHORIZE_SERVICE_CONNECTION:-true}"
AZDO_PIPELINE_NAME="${AZDO_PIPELINE_NAME:-coin-ops-terraform}"
AZDO_PIPELINE_YAML_PATH="${AZDO_PIPELINE_YAML_PATH:-azure-pipelines/terraform.yml}"
AZDO_REPOSITORY="${AZDO_REPOSITORY:-}"
AZDO_REPOSITORY_TYPE="${AZDO_REPOSITORY_TYPE:-tfsgit}"
AZDO_REPOSITORY_SERVICE_CONNECTION_ID="${AZDO_REPOSITORY_SERVICE_CONNECTION_ID:-}"
AZDO_BRANCH="${AZDO_BRANCH:-volynets-infra-dev}"
AZ_SP_CLIENT_SECRET="${AZ_SP_CLIENT_SECRET:-}"

# ------------------------------------------------------------
# Validate required variables
# ------------------------------------------------------------
for var in \
  AZ_GROUP_NAME \
  AZ_GROUP_LOCATION \
  AZ_SP_NAME \
  CREATE_BACKEND \
  AZ_STORAGE_ACCOUNT_NAME \
  AZ_CONTAINER_NAME \
  BACKEND_CONFIG_FILE \
  AZ_KEYVAULT_NAME \
  CREDENTIALS_FILE \
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

for bool_var in AZDO_CONFIGURE AZDO_CREATE_PIPELINE AZDO_AUTHORIZE_SERVICE_CONNECTION; do
  if [[ "${!bool_var}" != "true" && "${!bool_var}" != "false" ]]; then
    echo "ERROR: $bool_var must be either 'true' or 'false'."
    exit 1
  fi
done

if [[ ${#REQUIRED_SECRETS[@]} -eq 0 ]]; then
  echo "ERROR: REQUIRED_SECRETS is empty. Add at least one secret name."
  exit 1
fi

if [[ "$AZDO_CONFIGURE" == "true" ]]; then
  for var in AZDO_ORG_URL AZDO_PROJECT AZDO_PAT AZDO_SERVICE_CONNECTION_NAME; do
    if [[ -z "${!var}" ]]; then
      echo "ERROR: $var is required when AZDO_CONFIGURE=true."
      exit 1
    fi
  done

  if [[ "$AZDO_CREATE_PIPELINE" == "true" ]]; then
    for var in AZDO_PIPELINE_NAME AZDO_PIPELINE_YAML_PATH AZDO_REPOSITORY AZDO_REPOSITORY_TYPE AZDO_BRANCH; do
      if [[ -z "${!var}" ]]; then
        echo "ERROR: $var is required when AZDO_CREATE_PIPELINE=true."
        exit 1
      fi
    done

    if [[ "$AZDO_REPOSITORY_TYPE" == "github" && -z "$AZDO_REPOSITORY_SERVICE_CONNECTION_ID" ]]; then
      echo "ERROR: AZDO_REPOSITORY_SERVICE_CONNECTION_ID is required when AZDO_REPOSITORY_TYPE=github."
      exit 1
    fi
  fi
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

if [[ "$AZDO_CONFIGURE" == "true" ]]; then
  if ! az extension show --name azure-devops &>/dev/null; then
    echo "Azure DevOps CLI extension is not installed. Installing..."
    az extension add --name azure-devops
  fi
fi

# ------------------------------------------------------------
# Validate Azure authentication
# ------------------------------------------------------------
if ! az account show &>/dev/null; then
  echo "ERROR: Azure CLI is not authenticated. Run 'az login' first."
  exit 1
fi

AZ_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
AZ_TENANT_ID=$(az account show --query tenantId --output tsv)
AZ_SUBSCRIPTION_NAME=$(az account show --query name --output tsv)
echo "Using subscription: $AZ_SUBSCRIPTION_ID"
echo "Using subscription name: $AZ_SUBSCRIPTION_NAME"
echo "Using tenant: $AZ_TENANT_ID"

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
  echo "WARNING: Service Principal already exists: $AZ_SP_NAME"
  echo "WARNING: Existing client secret cannot be retrieved from Azure."
  echo "WARNING: Run 'az ad sp credential reset --name $AZ_SP_NAME' to generate a new secret."
  echo "WARNING: Or provide AZ_SP_CLIENT_SECRET when AZDO_CONFIGURE=true."

  AZ_CLIENT_ID=$SP_APP_ID
  AZ_CLIENT_SECRET="$AZ_SP_CLIENT_SECRET"
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
# 10) Configure Azure DevOps bridge
# ------------------------------------------------------------
AZDO_SERVICE_CONNECTION_ID=""
AZDO_PIPELINE_ID=""

if [[ "$AZDO_CONFIGURE" == "true" ]]; then
  echo ""
  echo "==> Step 10: Azure DevOps"

  if [[ -z "$AZ_CLIENT_SECRET" ]]; then
    echo "ERROR: Azure DevOps service connection needs a service principal secret."
    echo "ERROR: Re-run after resetting the SP secret or set AZ_SP_CLIENT_SECRET."
    exit 1
  fi

  echo "$AZDO_PAT" | az devops login --organization "$AZDO_ORG_URL" --only-show-errors

  az devops configure \
    --defaults organization="$AZDO_ORG_URL" project="$AZDO_PROJECT" \
    --only-show-errors

  AZDO_SERVICE_CONNECTION_ID=$(az devops service-endpoint list \
    --query "[?name=='$AZDO_SERVICE_CONNECTION_NAME'].id | [0]" \
    --output tsv)

  if [[ -n "$AZDO_SERVICE_CONNECTION_ID" ]]; then
    echo "Azure DevOps service connection already exists: $AZDO_SERVICE_CONNECTION_NAME"
  else
    AZDO_SERVICE_CONNECTION_OUTPUT=$(az devops service-endpoint azurerm create \
      --azure-rm-service-principal-id "$AZ_CLIENT_ID" \
      --azure-rm-service-principal-key "$AZ_CLIENT_SECRET" \
      --azure-rm-subscription-id "$AZ_SUBSCRIPTION_ID" \
      --azure-rm-subscription-name "$AZ_SUBSCRIPTION_NAME" \
      --azure-rm-tenant-id "$AZ_TENANT_ID" \
      --name "$AZDO_SERVICE_CONNECTION_NAME" \
      --output json)

    AZDO_SERVICE_CONNECTION_ID=$(echo "$AZDO_SERVICE_CONNECTION_OUTPUT" | jq -r '.id')
    echo "Azure DevOps service connection created: $AZDO_SERVICE_CONNECTION_NAME"
  fi

  if [[ "$AZDO_AUTHORIZE_SERVICE_CONNECTION" == "true" ]]; then
    az devops service-endpoint update \
      --id "$AZDO_SERVICE_CONNECTION_ID" \
      --enable-for-all true \
      --only-show-errors
    echo "Azure DevOps service connection authorized for pipelines"
  fi

  if [[ "$AZDO_CREATE_PIPELINE" == "true" ]]; then
    set_azdo_pipeline_variable() {
      local name="$1"
      local value="$2"

      if az pipelines variable list \
        --pipeline-id "$AZDO_PIPELINE_ID" \
        --query "$name" \
        --output tsv | grep -q .; then
        az pipelines variable update \
          --pipeline-id "$AZDO_PIPELINE_ID" \
          --name "$name" \
          --value "$value" \
          --allow-override true \
          --only-show-errors
      else
        az pipelines variable create \
          --pipeline-id "$AZDO_PIPELINE_ID" \
          --name "$name" \
          --value "$value" \
          --allow-override true \
          --only-show-errors
      fi
    }

    AZDO_PIPELINE_ID=$(az pipelines list \
      --name "$AZDO_PIPELINE_NAME" \
      --query "[0].id" \
      --output tsv)

    if [[ -n "$AZDO_PIPELINE_ID" ]]; then
      echo "Azure DevOps pipeline already exists: $AZDO_PIPELINE_NAME"
    else
      AZDO_PIPELINE_CREATE_ARGS=(
        --name "$AZDO_PIPELINE_NAME" \
        --repository "$AZDO_REPOSITORY" \
        --repository-type "$AZDO_REPOSITORY_TYPE" \
        --branch "$AZDO_BRANCH" \
        --yml-path "$AZDO_PIPELINE_YAML_PATH" \
        --skip-first-run true \
        --output json
      )

      if [[ -n "$AZDO_REPOSITORY_SERVICE_CONNECTION_ID" ]]; then
        AZDO_PIPELINE_CREATE_ARGS+=(--service-connection "$AZDO_REPOSITORY_SERVICE_CONNECTION_ID")
      fi

      AZDO_PIPELINE_OUTPUT=$(az pipelines create "${AZDO_PIPELINE_CREATE_ARGS[@]}")

      AZDO_PIPELINE_ID=$(echo "$AZDO_PIPELINE_OUTPUT" | jq -r '.id')
      echo "Azure DevOps pipeline created: $AZDO_PIPELINE_NAME"
    fi

    set_azdo_pipeline_variable "AZURE_SERVICE_CONNECTION" "$AZDO_SERVICE_CONNECTION_NAME"
    set_azdo_pipeline_variable "TF_BACKEND_RESOURCE_GROUP" "$AZ_GROUP_NAME"
    set_azdo_pipeline_variable "TF_BACKEND_STORAGE_ACCOUNT" "$AZ_STORAGE_ACCOUNT_NAME"
    set_azdo_pipeline_variable "TF_BACKEND_CONTAINER" "$AZ_CONTAINER_NAME"
    echo "Azure DevOps pipeline variables configured"
  else
    echo "AZDO_CREATE_PIPELINE is false, skipping Azure Pipeline creation"
  fi
else
  echo ""
  echo "==> Step 10: Azure DevOps"
  echo "AZDO_CONFIGURE is false, skipping Azure DevOps bridge setup"
fi

printf "\nDone!\n"
printf "  %-20s %s\n" "Resource group:" "$AZ_GROUP_NAME"
printf "  %-20s %s\n" "Key Vault:"      "$AZ_KEYVAULT_NAME"
printf "  %-20s %s\n" "Service principal:" "$AZ_SP_NAME"
printf "  %-20s %s\n" "State storage:"  "$([[ "$CREATE_BACKEND" == "true" ]] && echo "$AZ_STORAGE_ACCOUNT_NAME/$AZ_CONTAINER_NAME" || echo "skipped")"
printf "  %-20s %s\n" "Backend config:" "$([[ "$CREATE_BACKEND" == "true" ]] && echo "$BACKEND_CONFIG_FILE" || echo "skipped")"
printf "  %-20s %s\n" "Env file:"       "$CREDENTIALS_FILE"
printf "  %-20s %s\n" "AzDO connection:" "$([[ -n "$AZDO_SERVICE_CONNECTION_ID" ]] && echo "$AZDO_SERVICE_CONNECTION_NAME ($AZDO_SERVICE_CONNECTION_ID)" || echo "skipped")"
printf "  %-20s %s\n" "AzDO pipeline:" "$([[ -n "$AZDO_PIPELINE_ID" ]] && echo "$AZDO_PIPELINE_NAME ($AZDO_PIPELINE_ID)" || echo "skipped")"
printf "\nNext steps:\n"
printf "  update placeholder secrets in Azure Key Vault\n"
printf "  source %s\n" "$CREDENTIALS_FILE"
printf "  terraform init\n"
printf "\nIMPORTANT: Add %s to your .gitignore because it contains secrets.\n" "$CREDENTIALS_FILE"
