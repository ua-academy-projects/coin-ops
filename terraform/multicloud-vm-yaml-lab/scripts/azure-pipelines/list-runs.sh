#!/usr/bin/env bash
set -euo pipefail
test -s /tmp/coinops-ado-pat
export AZURE_DEVOPS_EXT_PAT="$(< /tmp/coinops-ado-pat)"
az pipelines runs list \
  --org "${AZDO_ORG:-https://dev.azure.com/coinops-leev1tan}" \
  --project "${AZDO_PROJECT:-CoinOps}" \
  --top "${1:-10}" \
  --query '[].{id:id,pipeline:definition.name,status:status,result:result,branch:sourceBranch,version:sourceVersion,queued:queueTime}' \
  -o json
