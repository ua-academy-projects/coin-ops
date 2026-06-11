#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
lab_sh="$repo_root/terraform/multicloud-vm-yaml-lab/scripts/lab.sh"

grep -Fq 'Cannot inspect tfstate resource group with this least-privilege identity' "$lab_sh"
grep -Fq 'State role metadata is not enumerable; Azure AD container access already verified' "$lab_sh"

if grep -Fq 'Missing tfstate resource group: $AZURE_STATE_RESOURCE_GROUP_NAME' "$lab_sh"; then
  echo "doctor still treats missing ARM visibility of the tfstate resource group as a bootstrap failure" >&2
  exit 1
fi

if grep -Fq 'Missing role: Storage Blob Data Contributor for tfstate' "$lab_sh"; then
  echo "doctor still treats role-assignment enumeration as stronger evidence than blob access" >&2
  exit 1
fi

echo "Azure doctor accepts capability-based tfstate access"
