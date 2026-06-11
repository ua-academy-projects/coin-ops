#!/usr/bin/env bash
set -euo pipefail

test -s /tmp/coinops-ado-pat
export AZURE_DEVOPS_EXT_PAT="$(< /tmp/coinops-ado-pat)"

org="https://dev.azure.com/coinops-leev1tan"
project="CoinOps"

echo "--- pipelines"
az pipelines list --org "$org" --project "$project" \
  --query '[].{id:id,name:name,path:path}' -o table

echo "--- variable groups"
az pipelines variable-group list --org "$org" --project "$project" \
  --query '[].{id:id,name:name}' -o table

echo "--- service endpoints"
az devops service-endpoint list --org "$org" --project "$project" \
  --query '[].{id:id,name:name,type:type,isReady:isReady}' -o table

echo "--- environments"
curl --fail --silent --show-error \
  --user ":$AZURE_DEVOPS_EXT_PAT" \
  "$org/$project/_apis/distributedtask/environments?api-version=7.1-preview.1" \
  | python3 -c 'import json,sys; data=json.load(sys.stdin); print("ID\tNAME"); [print("{}\t{}".format(row["id"], row["name"])) for row in data.get("value", [])]'

echo "--- environment checks"
curl --fail --silent --show-error \
  --user ":$AZURE_DEVOPS_EXT_PAT" \
  "$org/$project/_apis/pipelines/checks/configurations?resourceType=environment&resourceId=1&api-version=7.1-preview.1" \
  | python3 -c 'import json,sys; data=json.load(sys.stdin); print("TYPE\tTIMEOUT\tRESOURCE"); [print("{}\t{}\t{}".format(row.get("type",{}).get("name",""), row.get("timeout",""), row.get("resource",{}).get("name",""))) for row in data.get("value", [])]'
