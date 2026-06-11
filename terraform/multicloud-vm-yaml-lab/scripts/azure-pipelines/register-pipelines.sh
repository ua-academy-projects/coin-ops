#!/usr/bin/env bash
set -euo pipefail

test -s /tmp/coinops-ado-pat
export AZURE_DEVOPS_EXT_PAT="$(< /tmp/coinops-ado-pat)"

org="https://dev.azure.com/coinops-leev1tan"
project="CoinOps"
repository="https://github.com/ua-academy-projects/coin-ops"
branch="dev-Shabat-cloud"

github_endpoint_id="${1:-}"
if [[ -z "$github_endpoint_id" ]]; then
  github_endpoint_id="$(az devops service-endpoint list --org "$org" --project "$project" \
    --query "[?type=='github'].id | [0]" -o tsv)"
fi
test -n "$github_endpoint_id"

upsert_pipeline() {
  local name="$1"
  local yaml_path="$2"
  local pipeline_id

  pipeline_id="$(az pipelines list --org "$org" --project "$project" \
    --query "[?name=='$name'].id | [0]" -o tsv)"
  if [[ -z "$pipeline_id" ]]; then
    pipeline_id="$(az pipelines create \
      --org "$org" \
      --project "$project" \
      --name "$name" \
      --repository "$repository" \
      --repository-type github \
      --branch "$branch" \
      --yaml-path "$yaml_path" \
      --service-connection "$github_endpoint_id" \
      --skip-first-run true \
      --query id -o tsv)"
    echo "Created pipeline $name (id $pipeline_id)" >&2
  else
    echo "Reusing pipeline $name (id $pipeline_id)" >&2
  fi
  printf '%s' "$pipeline_id"
}

app_pipeline_id="$(upsert_pipeline coinops-app azure-pipelines-app.yml)"
lifecycle_pipeline_id="$(upsert_pipeline coinops-lab-lifecycle azure-pipelines-lifecycle.yml)"

printf 'github_endpoint_id=%s\n' "$github_endpoint_id"
printf 'app_pipeline_id=%s\n' "$app_pipeline_id"
printf 'lifecycle_pipeline_id=%s\n' "$lifecycle_pipeline_id"
