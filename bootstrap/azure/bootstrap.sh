#!/bin/bash

# ============================================================================
# Bootstrap Azure for Terraform
# ============================================================================
# Creates the Azure resources needed to store Terraform remote state:
#   - Resource Group   (container for all bootstrap resources)
#   - Storage Account  (the storage service that holds the state)
#   - Blob Container   (the actual bucket where terraform.tfstate lives)
#
# This script is idempotent — safe to run multiple times.
# State locking is handled natively by Azure via blob leases (no extra table).
# ============================================================================

set -euo pipefail

# ----------------------------------------------------------------------------
# Output colors
# ----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERR]${NC}  $1"; }

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
readonly AZURE_LOCATION="westeurope"
readonly RESOURCE_GROUP="tfstate-kazachuk-rg"
readonly STORAGE_ACCOUNT="tfstatekazachukazure"
readonly STATE_CONTAINER="tfstate"

# ----------------------------------------------------------------------------
# Prerequisites check
# ----------------------------------------------------------------------------
check_prerequisites() {
  log_info "Checking prerequisites..."

  if ! command -v az &> /dev/null; then
    log_error "Azure CLI is not installed. Run: brew install azure-cli"
    exit 1
  fi

  if ! az account show &>/dev/null; then
    log_error "Azure CLI is not authenticated. Run: az login"
    exit 1
  fi

  local sub_name
  sub_name=$(az account show --query name -o tsv)
  log_success "Authenticated. Active subscription: $sub_name"
}

# ----------------------------------------------------------------------------
# Create Resource Group
# ----------------------------------------------------------------------------
create_resource_group() {
  log_info "Checking Resource Group..."

  if az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    log_success "Resource Group already exists: $RESOURCE_GROUP"
  else
    log_info "Creating Resource Group: $RESOURCE_GROUP"
    az group create \
      --name "$RESOURCE_GROUP" \
      --location "$AZURE_LOCATION" \
      --output none
    log_success "Resource Group created"
  fi
}

# ----------------------------------------------------------------------------
# Create Storage Account
# ----------------------------------------------------------------------------
create_storage_account() {
  log_info "Checking Storage Account..."

  if az storage account show \
       --name "$STORAGE_ACCOUNT" \
       --resource-group "$RESOURCE_GROUP" &>/dev/null; then
    log_success "Storage Account already exists: $STORAGE_ACCOUNT"
  else
    log_info "Creating Storage Account: $STORAGE_ACCOUNT"
    az storage account create \
      --name "$STORAGE_ACCOUNT" \
      --resource-group "$RESOURCE_GROUP" \
      --location "$AZURE_LOCATION" \
      --sku "Standard_LRS" \
      --kind "StorageV2" \
      --min-tls-version "TLS1_2" \
      --allow-blob-public-access false \
      --output none
    log_success "Storage Account created"
  fi

  log_info "Enabling blob versioning..."
  az storage account blob-service-properties update \
    --account-name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --enable-versioning true \
    --output none
  log_success "Blob versioning enabled"
}

# ----------------------------------------------------------------------------
# Create Blob Container for Terraform state
# ----------------------------------------------------------------------------
create_state_container() {
  log_info "Checking Blob Container for Terraform state..."

  # Get the storage account key to authenticate the container operation
  local account_key
  account_key=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT" \
    --resource-group "$RESOURCE_GROUP" \
    --query '[0].value' -o tsv)

  if az storage container show \
       --name "$STATE_CONTAINER" \
       --account-name "$STORAGE_ACCOUNT" \
       --account-key "$account_key" &>/dev/null; then
    log_success "Blob Container already exists: $STATE_CONTAINER"
  else
    log_info "Creating Blob Container: $STATE_CONTAINER"
    az storage container create \
      --name "$STATE_CONTAINER" \
      --account-name "$STORAGE_ACCOUNT" \
      --account-key "$account_key" \
      --output none
    log_success "Blob Container created"
  fi
}

# ----------------------------------------------------------------------------
# Final summary
# ----------------------------------------------------------------------------
print_summary() {
  echo ""
  echo "============================================================================"
  log_success "Azure Bootstrap completed successfully!"
  echo "============================================================================"
  echo ""
  echo "  Location          : $AZURE_LOCATION"
  echo "  Resource Group    : $RESOURCE_GROUP"
  echo "  Storage Account   : $STORAGE_ACCOUNT"
  echo "  State Container   : $STATE_CONTAINER"
  echo ""
  echo "  Use these values in backends/azure.hcl:"
  echo ""
  echo "    resource_group_name  = \"$RESOURCE_GROUP\""
  echo "    storage_account_name = \"$STORAGE_ACCOUNT\""
  echo "    container_name       = \"$STATE_CONTAINER\""
  echo "    key                  = \"environments/learning/terraform.tfstate\""
  echo ""
  echo "============================================================================"
}

# ----------------------------------------------------------------------------
# Main flow
# ----------------------------------------------------------------------------
main() {
  echo "============================================================================"
  echo "  Azure Terraform Bootstrap"
  echo "============================================================================"
  echo ""

  check_prerequisites
  create_resource_group
  create_storage_account
  create_state_container
  print_summary
}

main "$@"