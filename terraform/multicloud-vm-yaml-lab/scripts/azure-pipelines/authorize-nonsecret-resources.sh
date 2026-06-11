#!/usr/bin/env bash
set -euo pipefail

test -s /tmp/coinops-ado-pat
export AZURE_DEVOPS_EXT_PAT="$(< /tmp/coinops-ado-pat)"

org="https://dev.azure.com/coinops-leev1tan"
project="CoinOps"

app_pipeline_id="$(az pipelines list --org "$org" --project "$project" \
  --query "[?name=='coinops-app'].id | [0]" -o tsv)"
lifecycle_pipeline_id="$(az pipelines list --org "$org" --project "$project" \
  --query "[?name=='coinops-lab-lifecycle'].id | [0]" -o tsv)"
variable_group_id="$(az pipelines variable-group list --org "$org" --project "$project" \
  --query "[?name=='coinops-cicd-secrets'].id | [0]" -o tsv)"

test -n "$app_pipeline_id"
test -n "$lifecycle_pipeline_id"
test -n "$variable_group_id"

authorize() {
  local resource_type="$1"
  local resource_id="$2"
  shift 2
  local pipelines_json="" pipeline_id body

  for pipeline_id in "$@"; do
    [[ -z "$pipelines_json" ]] || pipelines_json+=","
    pipelines_json+="{\"id\":$pipeline_id,\"authorized\":true}"
  done
  body="{\"pipelines\":[${pipelines_json}]}"

  curl --fail --silent --show-error \
    --user ":$AZURE_DEVOPS_EXT_PAT" \
    --request PATCH \
    --header "Content-Type: application/json" \
    --data "$body" \
    "$org/$project/_apis/pipelines/pipelinepermissions/$resource_type/$resource_id?api-version=7.1-preview.1" \
    >/dev/null
}

authorize variablegroup "$variable_group_id" "$app_pipeline_id" "$lifecycle_pipeline_id"
authorize environment 1 "$lifecycle_pipeline_id"

echo "Authorized variable group $variable_group_id for pipelines $app_pipeline_id and $lifecycle_pipeline_id"
echo "Authorized environment 1 for lifecycle pipeline $lifecycle_pipeline_id"
