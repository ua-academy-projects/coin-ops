#!/bin/bash
# =============================================================
# Azure Region Availability Checker
# Checks which regions support: Network, 1-vCPU VMs, PostgreSQL
#
# WHY 1 vCPU only:
#   Free account quota = 4 vCPU per region
#   We need 4 VMs, so each VM must use exactly 1 vCPU
#   4 VMs x 1 vCPU = 4 vCPU = fits in quota
#
# Usage: bash check-regions.sh
# Requires: coinops-rg resource group must exist
# =============================================================

RESOURCE_GROUP="coinops-tfstate-rg"

# Only 1 vCPU sizes — quota is 4 vCPU, need 4 VMs
# Standard_B1ls — 1 vCPU, 0.5GB RAM, ~$4/month  (cheapest)
# Standard_B1s  — 1 vCPU, 1GB RAM,   ~$8/month
# Standard_B1ms — 1 vCPU, 2GB RAM,   ~$15/month
VM_SIZES_TO_CHECK=(
  "Standard_B1ls"
  "Standard_B1s"
  "Standard_B1ms"
)

REGIONS=(
  eastus
  westus2
  australiaeast
  southeastasia
  northeurope
  swedencentral
  westeurope
  uksouth
  centralus
  southafricanorth
  centralindia
  eastasia
  japaneast
  canadacentral
  austriaeast
  spaincentral
  francecentral
  germanywestcentral
  italynorth
)

echo "============================================="
echo " Azure Region Availability Check"
echo " Subscription: $(az account show --query id -o tsv)"
echo " Checking: Network | 1-vCPU VMs | PostgreSQL"
echo "============================================="
echo ""

AVAILABLE_REGIONS=()

for region in "${REGIONS[@]}"; do
  printf "%-25s" "$region"

  # --- Check Network ---
  # Create test NSG — if blocked, region has policy restriction
  net_result=$(az network nsg create \
    --name "check-nsg-tmp" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$region" \
    --output none 2>/dev/null && echo "OK" || echo "blocked")

  az network nsg delete \
    --name "check-nsg-tmp" \
    --resource-group "$RESOURCE_GROUP" \
    --output none 2>/dev/null || true

  if [ "$net_result" != "OK" ]; then
    echo "Network: ✗  (policy blocked)"
    continue
  fi

  # --- Check VM sizes ---
  # az vm list-sizes returns TSV without quotes
  # format: NumberOfCores  MemoryInMB  Name  ...
  # we grep by exact name match in the line
  available_vm_sizes=()
  all_sizes=$(az vm list-sizes --location "$region" --output tsv 2>/dev/null)

  for vm_size in "${VM_SIZES_TO_CHECK[@]}"; do
    # grep for exact VM name in TSV (no quotes in TSV format)
    if echo "$all_sizes" | grep -qw "$vm_size"; then
      available_vm_sizes+=("$vm_size")
    fi
  done

  if [ ${#available_vm_sizes[@]} -gt 0 ]; then
    vm_icon="✓ (${available_vm_sizes[*]})"
    vm_ok=true
  else
    vm_icon="✗ no 1-vCPU VM available"
    vm_ok=false
  fi

  # --- Check PostgreSQL ---
  pg_count=$(az postgres flexible-server list-skus \
    --location "$region" \
    --output tsv 2>/dev/null \
    | head -1 \
    | grep -c "." 2>/dev/null || echo "0")

  if [ "$pg_count" -gt 0 ]; then
    pg_icon="✓"
    pg_ok=true
  else
    pg_icon="✗"
    pg_ok=false
  fi

  echo "Network: ✓  VMs: $vm_icon  PostgreSQL: $pg_icon"

  if [ "$vm_ok" == "true" ] && [ "$pg_ok" == "true" ]; then
    AVAILABLE_REGIONS+=("$region")
  fi
done

echo ""
echo "============================================="
echo " Regions with ALL services available:"
echo " (Network + 1-vCPU VM + PostgreSQL)"
echo "============================================="
if [ ${#AVAILABLE_REGIONS[@]} -eq 0 ]; then
  echo " None found — check quota or try different VM sizes"
else
  for r in "${AVAILABLE_REGIONS[@]}"; do
    echo "  ✓ $r"
  done
fi
echo "============================================="
echo ""
echo " Quota reminder: Free account = 4 vCPU per region"
echo " 4 VMs x 1 vCPU = 4 vCPU = fits perfectly"
echo "============================================="