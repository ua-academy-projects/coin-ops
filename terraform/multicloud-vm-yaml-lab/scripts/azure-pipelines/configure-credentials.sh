#!/usr/bin/env bash
set -euo pipefail

org="https://dev.azure.com/coinops-leev1tan"
project="CoinOps"
repo="/home/leev1tan/projects/softserv-internship"
lab="$repo/terraform/multicloud-vm-yaml-lab"

test -s /tmp/coinops-ado-pat
export AZURE_DEVOPS_EXT_PAT="$(< /tmp/coinops-ado-pat)"

set -a
# shellcheck disable=SC1091
. "$repo/.env"
# shellcheck disable=SC1091
. "$lab/.env.azure"
set +a

aws_access_key_id="$(aws configure get aws_access_key_id --profile coinops-admin)"
aws_secret_access_key="$(aws configure get aws_secret_access_key --profile coinops-admin)"
subscription_name="$(az account show --subscription "$ARM_SUBSCRIPTION_ID" --query name -o tsv)"

test -n "$aws_access_key_id"
test -n "$aws_secret_access_key"
test -n "$ARM_CLIENT_ID"
test -n "$ARM_CLIENT_SECRET"
test -n "$TF_VAR_github_oauth_client_id"
test -n "$TF_VAR_github_oauth_client_secret"

group_id="$(az pipelines variable-group list \
  --organization "$org" \
  --project "$project" \
  --query "[?name=='coinops-cicd-secrets'].id | [0]" \
  -o tsv)"

if [[ -z "$group_id" ]]; then
  group_id="$(
    az pipelines variable-group create \
      --organization "$org" \
      --project "$project" \
      --name coinops-cicd-secrets \
      --description "Durable multicloud lab credentials for CoinOps Azure Pipelines" \
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
      --query id \
      -o tsv
  )"
fi

upsert_secret() {
  local name="$1"
  local value="$2"
  export "AZURE_DEVOPS_EXT_PIPELINE_VAR_${name}=$value"
  if az pipelines variable-group variable list \
    --organization "$org" \
    --project "$project" \
    --group-id "$group_id" \
    --query "contains(keys(@), '$name')" -o tsv | grep -qi true; then
    az pipelines variable-group variable update \
      --organization "$org" \
      --project "$project" \
      --group-id "$group_id" \
      --name "$name" \
      --secret true \
      --output none
  else
    az pipelines variable-group variable create \
      --organization "$org" \
      --project "$project" \
      --group-id "$group_id" \
      --name "$name" \
      --secret true \
      --output none
  fi
  unset "AZURE_DEVOPS_EXT_PIPELINE_VAR_${name}"
}

upsert_secret AWS_ACCESS_KEY_ID "$aws_access_key_id"
upsert_secret AWS_SECRET_ACCESS_KEY "$aws_secret_access_key"
upsert_secret DB_PASSWORD "$DB_PASSWORD"
upsert_secret RABBITMQ_PASSWORD "$RABBITMQ_PASSWORD"
upsert_secret TAILSCALE_AUTH_KEY "$TAILSCALE_AUTH_KEY"
upsert_secret GHCR_TOKEN "$GHCR_TOKEN"
# The existing classic token has both repo and write:packages scopes.
upsert_secret GHCR_PUSH_TOKEN "$GHCR_TOKEN"
upsert_secret GITHUB_GITOPS_TOKEN "$GHCR_TOKEN"
upsert_secret CLOUDFLARE_API_TOKEN "$CLOUDFLARE_API_TOKEN"
upsert_secret TF_VAR_github_oauth_client_id "$TF_VAR_github_oauth_client_id"
upsert_secret TF_VAR_github_oauth_client_secret "$TF_VAR_github_oauth_client_secret"

endpoint_id="$(az devops service-endpoint list \
  --organization "$org" \
  --project "$project" \
  --query "[?name=='coinops-terraform-azure'].id | [0]" \
  -o tsv)"

if [[ -z "$endpoint_id" ]]; then
  export AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY="$ARM_CLIENT_SECRET"
  endpoint_id="$(
    az devops service-endpoint azurerm create \
      --organization "$org" \
      --project "$project" \
      --name coinops-terraform-azure \
      --azure-rm-service-principal-id "$ARM_CLIENT_ID" \
      --azure-rm-subscription-id "$ARM_SUBSCRIPTION_ID" \
      --azure-rm-subscription-name "$subscription_name" \
      --azure-rm-tenant-id "$ARM_TENANT_ID" \
      --query id \
      -o tsv
  )"
  unset AZURE_DEVOPS_EXT_AZURE_RM_SERVICE_PRINCIPAL_KEY
fi

upload_secure_file() {
  local path="$1"
  local name="$2"
  local existing_id

  test -s "$path"
  existing_id="$(curl --fail --silent --show-error \
    --user ":$AZURE_DEVOPS_EXT_PAT" \
    "$org/$project/_apis/distributedtask/securefiles?api-version=7.1-preview.1" \
    | python3 -c 'import json,sys; name=sys.argv[1]; rows=json.load(sys.stdin).get("value", []); print(next((str(row["id"]) for row in rows if row.get("name") == name), ""))' "$name")"

  if [[ -n "$existing_id" ]]; then
    printf 'secure_file_%s=%s\n' "$name" "$existing_id"
    return
  fi

  curl --fail --silent --show-error \
    --user ":$AZURE_DEVOPS_EXT_PAT" \
    --request POST \
    --header "Content-Type: application/octet-stream" \
    --data-binary "@$path" \
    "$org/$project/_apis/distributedtask/securefiles?name=$name&api-version=7.1-preview.1" \
    | python3 -c 'import json,sys; row=json.load(sys.stdin); print("secure_file_{}={}".format(row["name"], row["id"]))'
}

upload_secure_file "/home/leev1tan/.ssh/coinops_gcp_jump" "coinops_gcp_jump"
upload_secure_file "$lab/keys/coinops-terraform-key.json" "coinops-gcp-terraform.json"

printf 'variable_group_id=%s\n' "$group_id"
printf 'service_endpoint_id=%s\n' "$endpoint_id"
