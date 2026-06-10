#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
providers_tf="$repo_root/terraform/multicloud-vm-yaml-lab/providers.tf"

grep -Eq 'purge_soft_delete_on_destroy[[:space:]]*=[[:space:]]*false' "$providers_tf"
grep -Eq 'recover_soft_deleted_key_vaults[[:space:]]*=[[:space:]]*true' "$providers_tf"

echo "Azure Key Vault lifecycle contract is complete"
