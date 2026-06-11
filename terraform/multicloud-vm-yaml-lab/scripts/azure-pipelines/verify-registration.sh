#!/usr/bin/env bash
set -euo pipefail

test -s /tmp/coinops-ado-pat
export AZURE_DEVOPS_EXT_PAT="$(< /tmp/coinops-ado-pat)"

org="https://dev.azure.com/coinops-leev1tan"
project="CoinOps"

echo "--- pipelines"
az pipelines list --org "$org" --project "$project" \
  --query '[].{id:id,name:name,queueStatus:queueStatus,path:path}' -o table

echo "--- source definitions"
for id in 1 2; do
  az pipelines show --org "$org" --project "$project" --id "$id" \
    --query '{id:id,name:name,yaml:process.yamlFilename,repo:repository.name,repoType:repository.type,branch:repository.defaultBranch,endpoint:repository.properties.connectedServiceId}' \
    -o json
done

echo "--- service endpoints"
az devops service-endpoint list --org "$org" --project "$project" \
  --query '[].{id:id,name:name,type:type,isReady:isReady}' -o table

echo "--- variable group keys"
az pipelines variable-group show --org "$org" --project "$project" --group-id 1 -o json \
  | python3 -c 'import json,sys; row=json.load(sys.stdin); print("ID={} NAME={} AUTHORIZED={}".format(row["id"], row["name"], row.get("authorized"))); print("NAME\tSECRET"); [print("{}\t{}".format(name, bool(meta.get("isSecret")))) for name,meta in sorted(row.get("variables",{}).items())]'

echo "--- secure files"
secure_files_json="$(curl --fail --silent --show-error \
  --user ":$AZURE_DEVOPS_EXT_PAT" \
  "$org/$project/_apis/distributedtask/securefiles?api-version=7.1-preview.1")"
python3 -c 'import json,sys; rows=json.load(sys.stdin).get("value", []); print("ID\tNAME"); [print("{}\t{}".format(row["id"], row["name"])) for row in rows]' <<<"$secure_files_json"

echo "--- explicit permissions"
azure_endpoint_id="$(az devops service-endpoint list --org "$org" --project "$project" --query "[?name=='coinops-terraform-azure'].id | [0]" -o tsv)"
ssh_secure_file_id="$(python3 -c 'import json,sys; rows=json.load(sys.stdin).get("value", []); print(next((str(row["id"]) for row in rows if row.get("name") == "coinops_gcp_jump"), ""))' <<<"$secure_files_json")"
gcp_secure_file_id="$(python3 -c 'import json,sys; rows=json.load(sys.stdin).get("value", []); print(next((str(row["id"]) for row in rows if row.get("name") == "coinops-gcp-terraform.json"), ""))' <<<"$secure_files_json")"

for resource in variablegroup/1 environment/1 endpoint/"$azure_endpoint_id" securefile/"$ssh_secure_file_id" securefile/"$gcp_secure_file_id"; do
  curl --fail --silent --show-error \
    --user ":$AZURE_DEVOPS_EXT_PAT" \
    "$org/$project/_apis/pipelines/pipelinepermissions/$resource?api-version=7.1-preview.1" \
    | python3 -c 'import json,sys; row=json.load(sys.stdin); print("resource={} all={} pipelines={}".format(sys.argv[1], row.get("allPipelines",{}).get("authorized"), [(p.get("id"),p.get("authorized")) for p in row.get("pipelines",[])]))' "$resource"
done
