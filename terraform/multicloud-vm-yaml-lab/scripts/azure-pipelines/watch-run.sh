#!/usr/bin/env bash
set -euo pipefail
test -s /tmp/coinops-ado-pat
export AZURE_DEVOPS_EXT_PAT="$(< /tmp/coinops-ado-pat)"

org="${AZDO_ORG:-https://dev.azure.com/coinops-leev1tan}"
project="${AZDO_PROJECT:-CoinOps}"
run_id="${1:-$(az pipelines runs list --org "$org" --project "$project" --top 1 --query '[0].id' -o tsv)}"
test -n "$run_id"
echo "run_id=$run_id"

while true; do
  read -r status result <<<"$(az pipelines runs show --org "$org" --project "$project" --id "$run_id" --query '[status,result]' -o tsv)"
  printf 'status=%s result=%s\n' "$status" "${result:-pending}"
  [[ "$status" == "completed" ]] && break
  sleep 20
done

az pipelines runs show --org "$org" --project "$project" --id "$run_id" \
  --query '{id:id,pipeline:definition.name,status:status,result:result,sourceBranch:sourceBranch,sourceVersion:sourceVersion,url:url}' -o json
[[ "$result" == "succeeded" ]]
