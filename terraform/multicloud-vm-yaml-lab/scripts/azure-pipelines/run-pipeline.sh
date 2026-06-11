#!/usr/bin/env bash
set -euo pipefail

test -s /tmp/coinops-ado-pat
export AZURE_DEVOPS_EXT_PAT="$(< /tmp/coinops-ado-pat)"

org="${AZDO_ORG:-https://dev.azure.com/coinops-leev1tan}"
project="${AZDO_PROJECT:-CoinOps}"
pipeline="${1:?usage: run_ado_pipeline.sh PIPELINE [BRANCH] [NAME=VALUE ...]}"
branch="${2:-dev-Shabat-cloud}"
shift 2 || true

args=(az pipelines run --org "$org" --project "$project" --name "$pipeline" --branch "$branch")
if (($#)); then
  args+=(--parameters "$@")
fi

run_id="$("${args[@]}" --query id -o tsv)"
echo "run_id=$run_id"

while true; do
  read -r status result <<<"$(az pipelines runs show --org "$org" --project "$project" --id "$run_id" --query '[status,result]' -o tsv)"
  printf 'status=%s result=%s\n' "$status" "${result:-pending}"
  [[ "$status" == "completed" ]] && break
  sleep 20
done

az pipelines runs show --org "$org" --project "$project" --id "$run_id" \
  --query '{id:id,status:status,result:result,sourceBranch:sourceBranch,sourceVersion:sourceVersion,url:url}' -o json

[[ "$result" == "succeeded" ]]
