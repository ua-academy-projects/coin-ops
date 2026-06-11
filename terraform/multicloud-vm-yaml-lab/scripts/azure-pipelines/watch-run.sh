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
  run_json="$(az pipelines runs show --org "$org" --project "$project" --id "$run_id" -o json)"
  read -r status result < <(python3 -c 'import json,sys; row=json.load(sys.stdin); status = row.get("status") or "unknown"; result = row.get("result") or "pending"; print(status, result)' <<<"$run_json")
  printf 'status=%s result=%s\n' "$status" "$result"
  [[ "$status" == "completed" && "$result" != "pending" ]] && break
  sleep 20
done

az pipelines runs show --org "$org" --project "$project" --id "$run_id" \
  --query '{id:id,pipeline:definition.name,status:status,result:result,sourceBranch:sourceBranch,sourceVersion:sourceVersion,url:url}' -o json
[[ "$result" == "succeeded" ]]
