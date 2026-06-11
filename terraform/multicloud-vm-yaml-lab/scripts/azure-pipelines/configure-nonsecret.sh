#!/usr/bin/env bash
set -euo pipefail

test -s /tmp/coinops-ado-pat
export AZURE_DEVOPS_EXT_PAT="$(< /tmp/coinops-ado-pat)"

org="https://dev.azure.com/coinops-leev1tan"
project="CoinOps"
group_name="coinops-cicd-secrets"

group_id="$(az pipelines variable-group list --org "$org" --project "$project" \
  --query "[?name=='$group_name'].id | [0]" -o tsv)"

if [[ -z "$group_id" ]]; then
  group_id="$(az pipelines variable-group create \
    --org "$org" --project "$project" \
    --name "$group_name" \
    --authorize false \
    --variables \
      AWS_PROFILE=coinops-admin \
      AWS_REGION=eu-central-1 \
      GCP_PROJECT_ID=coinops-student-leev1tan-001 \
      GHCR_USERNAME=leev1tan \
      AZURE_WORKLOAD_RESOURCE_GROUP=coinops-lab-rg \
      AZURE_TFSTATE_RESOURCE_GROUP=coinops-tfstate-rg \
      AZURE_TFSTATE_STORAGE_ACCOUNT=coinopslabtfstate \
      AZURE_TFSTATE_CONTAINER=tfstate \
      AZURE_TFSTATE_KEY=multicloud-vm-yaml-lab/terraform.tfstate \
    --query id -o tsv)"
  echo "Created variable group $group_name (id $group_id)"
else
  echo "Reusing variable group $group_name (id $group_id)"
  declare -A variables=(
    [AWS_PROFILE]=coinops-admin
    [AWS_REGION]=eu-central-1
    [GCP_PROJECT_ID]=coinops-student-leev1tan-001
    [GHCR_USERNAME]=leev1tan
    [AZURE_WORKLOAD_RESOURCE_GROUP]=coinops-lab-rg
    [AZURE_TFSTATE_RESOURCE_GROUP]=coinops-tfstate-rg
    [AZURE_TFSTATE_STORAGE_ACCOUNT]=coinopslabtfstate
    [AZURE_TFSTATE_CONTAINER]=tfstate
    [AZURE_TFSTATE_KEY]=multicloud-vm-yaml-lab/terraform.tfstate
  )
  for name in "${!variables[@]}"; do
    if az pipelines variable-group variable list --org "$org" --project "$project" \
      --group-id "$group_id" --query "contains(keys(@), '$name')" -o tsv | grep -qi true; then
      az pipelines variable-group variable update --org "$org" --project "$project" \
        --group-id "$group_id" --name "$name" --value "${variables[$name]}" >/dev/null
    else
      az pipelines variable-group variable create --org "$org" --project "$project" \
        --group-id "$group_id" --name "$name" --value "${variables[$name]}" >/dev/null
    fi
  done
fi

az pipelines variable-group show --org "$org" --project "$project" --group-id "$group_id" \
  --query '{id:id,name:name,authorized:authorized,variables:keys(variables)}' -o json
