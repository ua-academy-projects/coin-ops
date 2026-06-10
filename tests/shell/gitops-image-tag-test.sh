#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
app_yaml="$repo_root/gitops/apps/coinops-app.yaml"
values_dev="$repo_root/charts/coinops-app/values-dev.yaml"

test -f "$values_dev"
grep -Fq 'tag: "dev-latest"' "$values_dev"
grep -Fq -- '- values.yaml' "$app_yaml"
grep -Fq -- '- values-dev.yaml' "$app_yaml"
if grep -Fq 'valuesObject:' "$app_yaml"; then
  echo "coinops-app.yaml still embeds mutable Helm values" >&2
  exit 1
fi

echo "GitOps image tag contract is complete"
