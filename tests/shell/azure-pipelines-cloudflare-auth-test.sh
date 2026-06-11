#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
runner="$repo_root/.azure-pipelines/templates/run-lab-action.yml"
credentials="$repo_root/terraform/multicloud-vm-yaml-lab/scripts/azure-pipelines/configure-credentials.sh"

grep -Fq 'TF_VAR_github_oauth_client_id: $(TF_VAR_github_oauth_client_id)' "$runner"
grep -Fq 'TF_VAR_github_oauth_client_secret: $(TF_VAR_github_oauth_client_secret)' "$runner"
grep -Fq 'upsert_secret TF_VAR_github_oauth_client_id "$TF_VAR_github_oauth_client_id"' "$credentials"
grep -Fq 'upsert_secret TF_VAR_github_oauth_client_secret "$TF_VAR_github_oauth_client_secret"' "$credentials"

bash -n "$credentials"

echo "Azure lifecycle preserves Cloudflare GitHub identity-provider credentials"
