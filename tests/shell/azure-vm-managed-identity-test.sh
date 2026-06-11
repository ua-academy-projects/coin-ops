#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
compute="$repo_root/terraform/multicloud-vm-yaml-lab/modules/azure-stack/modules/compute/main.tf"

identity_count="$(grep -Ec 'type[[:space:]]*=[[:space:]]*"SystemAssigned"' "$compute")"
if [[ "$identity_count" != "3" ]]; then
  echo "Expected system-assigned identities on bastion, k3s, and app VMs; found $identity_count" >&2
  exit 1
fi

grep -Fq 'resource "azurerm_linux_virtual_machine" "bastion"' "$compute"
grep -Fq 'resource "azurerm_linux_virtual_machine" "k3s"' "$compute"
echo "All Azure VM classes retain managed identity"
