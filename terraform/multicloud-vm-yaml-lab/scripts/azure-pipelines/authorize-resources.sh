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
azure_endpoint_id="$(az devops service-endpoint list --org "$org" --project "$project" \
  --query "[?name=='coinops-terraform-azure'].id | [0]" -o tsv)"

test -n "$app_pipeline_id"
test -n "$lifecycle_pipeline_id"
test -n "$variable_group_id"
test -n "$azure_endpoint_id"

secure_files_json="$(curl --fail --silent --show-error \
  --user ":$AZURE_DEVOPS_EXT_PAT" \
  "$org/$project/_apis/distributedtask/securefiles?api-version=7.1-preview.1")"
ssh_secure_file_id="$(python3 -c 'import json,sys; rows=json.load(sys.stdin).get("value", []); print(next((str(row["id"]) for row in rows if row.get("name") == "coinops_gcp_jump"), ""))' <<<"$secure_files_json")"
gcp_secure_file_id="$(python3 -c 'import json,sys; rows=json.load(sys.stdin).get("value", []); print(next((str(row["id"]) for row in rows if row.get("name") == "coinops-gcp-terraform.json"), ""))' <<<"$secure_files_json")"
test -n "$ssh_secure_file_id"
test -n "$gcp_secure_file_id"

authorize() {
  local resource_type="$1"
  local resource_id="$2"
  shift 2
  local body pipelines_json="" pipeline_id

  for pipeline_id in "$@"; do
    if [[ -n "$pipelines_json" ]]; then
      pipelines_json+=","
    fi
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
authorize endpoint "$azure_endpoint_id" "$lifecycle_pipeline_id"
authorize securefile "$ssh_secure_file_id" "$lifecycle_pipeline_id"
authorize securefile "$gcp_secure_file_id" "$lifecycle_pipeline_id"
authorize environment 1 "$lifecycle_pipeline_id"

echo "Authorized variable group for both pipelines"
echo "Authorized Azure endpoint, Secure Files, and lifecycle environment for pipeline $lifecycle_pipeline_id"
