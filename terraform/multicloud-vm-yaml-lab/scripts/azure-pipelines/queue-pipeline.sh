#!/usr/bin/env bash
set -euo pipefail

test -s /tmp/coinops-ado-pat
export AZURE_DEVOPS_EXT_PAT="$(< /tmp/coinops-ado-pat)"

org="${AZDO_ORG:-https://dev.azure.com/coinops-leev1tan}"
project="${AZDO_PROJECT:-CoinOps}"
pipeline="${1:?usage: queue_ado_pipeline.sh PIPELINE [BRANCH] [NAME=VALUE ...]}"
branch="${2:-dev-Shabat-cloud}"
shift 2 || true

args=(az pipelines run --org "$org" --project "$project" --name "$pipeline" --branch "$branch")
if (($#)); then
  args+=(--parameters "$@")
fi

"${args[@]}" --query '{id:id,pipeline:definition.name,status:status,branch:sourceBranch,version:sourceVersion}' -o json
