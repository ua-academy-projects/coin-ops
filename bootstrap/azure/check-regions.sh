#!/bin/bash
REGIONS=(spaincentral francecentral germanywestcentral swedencentral italynorth)

for region in "${REGIONS[@]}"; do
  echo "--- $region ---"
  
  # vCPU quota
  az vm list-usage --location "$region" --output tsv 2>/dev/null \
    | grep "Total Regional vCPUs" \
    | awk '{print "  vCPU quota:", $NF}'

  # Network provider availability
  vnet=$(az provider show \
    --namespace Microsoft.Network \
    --query "resourceTypes[?resourceType=='virtualNetworks'].locations" \
    --output tsv 2>/dev/null | grep -ic "$region" || echo "0")
  
  nsg=$(az provider show \
    --namespace Microsoft.Network \
    --query "resourceTypes[?resourceType=='networkSecurityGroups'].locations" \
    --output tsv 2>/dev/null | grep -ic "$region" || echo "0")

  pip=$(az provider show \
    --namespace Microsoft.Network \
    --query "resourceTypes[?resourceType=='publicIPAddresses'].locations" \
    --output tsv 2>/dev/null | grep -ic "$region" || echo "0")

  [ "$vnet" -gt 0 ] && echo "  VNet: ✓" || echo "  VNet: ✗"
  [ "$nsg" -gt 0 ]  && echo "  NSG: ✓"  || echo "  NSG: ✗"
  [ "$pip" -gt 0 ]  && echo "  PublicIP: ✓" || echo "  PublicIP: ✗"

  # VM sizes
  for size in Standard_B1s Standard_B2s_v2; do
    result=$(az vm list-skus \
      --location "$region" \
      --size "$size" \
      --resource-type virtualMachines \
      --output tsv 2>/dev/null | grep -c "$size" || echo "0")
    [ "$result" -gt 0 ] && echo "  $size: ✓" || echo "  $size: ✗"
  done

  echo ""
done