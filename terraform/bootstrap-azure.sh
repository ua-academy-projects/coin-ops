#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash bootstrap-azure.sh [--activate-backend]

Bootstraps Azure account-side prerequisites for coin-ops:
  - registers required Azure resource providers
  - creates or refreshes the Terraform service principal
  - grants RBAC needed for Terraform and Key Vault
  - writes local Azure env / tfvars / ansible config helpers

Backend behavior:
  - if terraform/config/clouds.json sets clouds.control_plane = "azure",
    the script prepares Azure Storage backend resources and rewrites
    terraform/backend.active.tf
  - otherwise, backend.active.tf is left untouched unless you pass
    --activate-backend explicitly
EOF
}

ACTIVATE_BACKEND=false
if [[ "${1:-}" == "--activate-backend" ]]; then
  ACTIVATE_BACKEND=true
elif [[ -n "${1:-}" ]]; then
  usage
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MAPPING_PATH="${SCRIPT_DIR}/config/cloud_mappings.json"
CONFIG_DIR="${SCRIPT_DIR}/config"
BACKEND_TEMPLATE_PATH="${SCRIPT_DIR}/backends/backend.azure.tf.tmpl"
BACKEND_ACTIVE_PATH="${SCRIPT_DIR}/backend.active.tf"
CONFIG_FILES=(clouds.json general.json deploy.json database.json dns.json secrets.json instances.json)

if [ ! -f "${MAPPING_PATH}" ]; then
  echo "Missing cloud mappings file: ${MAPPING_PATH}"
  exit 1
fi

for config_file in "${CONFIG_FILES[@]}"; do
  if [ ! -f "${CONFIG_DIR}/${config_file}" ]; then
    echo "Missing Terraform config file: ${CONFIG_DIR}/${config_file}"
    exit 1
  fi
done

if [ ! -f "${BACKEND_TEMPLATE_PATH}" ]; then
  echo "Missing backend template file: ${BACKEND_TEMPLATE_PATH}"
  exit 1
fi

read_config() {
  python3 - "$CONFIG_DIR" "$1" <<'PY'
import json
import pathlib
import sys

config_dir = pathlib.Path(sys.argv[1])
expression = sys.argv[2]
data = {}
for name in ("clouds.json", "general.json", "deploy.json", "database.json", "dns.json", "secrets.json", "instances.json"):
    with (config_dir / name).open(encoding="utf-8") as handle:
        data.update(json.load(handle))

value = eval(expression, {"__builtins__": {}}, {"data": data})
if isinstance(value, bool):
    print(str(value).lower())
else:
    print(value)
PY
}

SP_NAME="$(read_config 'data["clouds"]["providers"]["azure"]["terraform_identity"]["name"]')"
CONTROL_PLANE="$(read_config 'data["clouds"]["control_plane"]')"
REGION_PROFILE="$(read_config 'data["general"]["region_profile"]')"
LOCATION="$(python3 -c 'import json,sys; data=json.load(open(sys.argv[1], encoding="utf-8")); print(data["regions"]["azure"][sys.argv[2]]["location"])' "${MAPPING_PATH}" "${REGION_PROFILE}")"
SUBSCRIPTION_ID="$(read_config 'data["clouds"]["providers"]["azure"]["account"].get("subscription_id", "")')"
TENANT_ID="$(read_config 'data["clouds"]["providers"]["azure"]["account"].get("tenant_id", "")')"
RESOURCE_GROUP_NAME="$(read_config 'data["clouds"]["providers"]["azure"]["account"].get("resource_group_name", "coin-ops-azure-rg")')"
STATE_RESOURCE_GROUP_NAME="$(read_config 'data["clouds"]["backends"]["azure"].get("resource_group_name", data["clouds"]["providers"]["azure"]["account"].get("state_resource_group_name", "coin-ops-tfstate-rg"))')"
STORAGE_ACCOUNT_NAME="$(read_config 'data["clouds"]["backends"]["azure"].get("storage_account_name", data["clouds"]["providers"]["azure"]["account"].get("storage_account_name", "coinopstfstate"))')"
CONTAINER_NAME="$(read_config 'data["clouds"]["backends"]["azure"].get("container_name", data["clouds"]["providers"]["azure"]["account"].get("storage_container_name", "tfstate"))')"
STATE_KEY="$(read_config 'data["clouds"]["backends"]["azure"].get("key", "infra/state/terraform.tfstate")')"
KEY_VAULT_NAME="$(read_config 'data["clouds"]["providers"]["azure"]["account"].get("key_vault_name", "coinops-kv")')"

GENERATED_AZURE_ENV_PATH="${REPO_ROOT}/local/generated-azure-env.sh"
GENERATED_ACTIVE_ENV_PATH="${REPO_ROOT}/local/generated-env.sh"
SSH_PUBLIC_KEY_PATH="${HOME}/.ssh/ssh-key-coin-ops.pub"

if [[ "${CONTROL_PLANE}" == "azure" ]]; then
  ACTIVATE_BACKEND=true
fi

echo "Starting Azure bootstrap for subscription ${SUBSCRIPTION_ID:-<current>}, location ${LOCATION}"

az account show > /dev/null

if [ -n "${SUBSCRIPTION_ID}" ]; then
  az account set --subscription "${SUBSCRIPTION_ID}"
else
  SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
fi

if [ -z "${TENANT_ID}" ]; then
  TENANT_ID="$(az account show --query tenantId -o tsv)"
fi

echo "Registering required Azure resource providers..."
for namespace in \
  Microsoft.Network \
  Microsoft.Compute \
  Microsoft.Storage \
  Microsoft.KeyVault \
  Microsoft.DBforPostgreSQL
do
  az provider register --namespace "${namespace}" > /dev/null
done

echo "Creating or refreshing Azure service principal: ${SP_NAME}"
if az ad sp list --display-name "${SP_NAME}" --query '[0].appId' -o tsv | grep -q .; then
  APP_ID="$(az ad sp list --display-name "${SP_NAME}" --query '[0].appId' -o tsv)"
  SP_JSON="$(az ad app credential reset --id "${APP_ID}" --display-name codex-bootstrap -o json)"
else
  SP_JSON="$(az ad sp create-for-rbac --name "${SP_NAME}" --role Contributor --scopes "/subscriptions/${SUBSCRIPTION_ID}" -o json)"
  APP_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["appId"])' <<< "${SP_JSON}")"
fi

CLIENT_ID="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["appId"])' <<< "${SP_JSON}")"
CLIENT_SECRET="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["password"])' <<< "${SP_JSON}")"
TENANT_ID_FROM_SP="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["tenant"])' <<< "${SP_JSON}")"
TENANT_ID="${TENANT_ID:-$TENANT_ID_FROM_SP}"

SP_OBJECT_ID="$(az ad sp show --id "${CLIENT_ID}" --query id -o tsv)"

echo "Assigning Azure roles..."
az role assignment create --assignee-object-id "${SP_OBJECT_ID}" --assignee-principal-type ServicePrincipal --role "Contributor" --scope "/subscriptions/${SUBSCRIPTION_ID}" > /dev/null 2>&1 || true
az role assignment create --assignee-object-id "${SP_OBJECT_ID}" --assignee-principal-type ServicePrincipal --role "Key Vault Administrator" --scope "/subscriptions/${SUBSCRIPTION_ID}" > /dev/null 2>&1 || true

if [[ "${ACTIVATE_BACKEND}" == "true" ]]; then
  echo "Ensuring backend resource group exists: ${STATE_RESOURCE_GROUP_NAME}"
  az group create --name "${STATE_RESOURCE_GROUP_NAME}" --location "${LOCATION}" > /dev/null

  echo "Ensuring storage account exists: ${STORAGE_ACCOUNT_NAME}"
  if ! az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${STATE_RESOURCE_GROUP_NAME}" > /dev/null 2>&1; then
    az storage account create \
      --name "${STORAGE_ACCOUNT_NAME}" \
      --resource-group "${STATE_RESOURCE_GROUP_NAME}" \
      --location "${LOCATION}" \
      --sku Standard_LRS \
      --kind StorageV2 \
      --allow-blob-public-access false > /dev/null
  fi

  echo "Ensuring state container exists: ${CONTAINER_NAME}"
  az storage container create \
    --name "${CONTAINER_NAME}" \
    --account-name "${STORAGE_ACCOUNT_NAME}" \
    --auth-mode login > /dev/null

  STORAGE_SCOPE="$(az storage account show --name "${STORAGE_ACCOUNT_NAME}" --resource-group "${STATE_RESOURCE_GROUP_NAME}" --query id -o tsv)"
  az role assignment create --assignee-object-id "${SP_OBJECT_ID}" --assignee-principal-type ServicePrincipal --role "Storage Blob Data Owner" --scope "${STORAGE_SCOPE}" > /dev/null 2>&1 || true

  echo "Writing active Terraform backend at ${BACKEND_ACTIVE_PATH}..."
  python3 - <<'PY' "${BACKEND_TEMPLATE_PATH}" "${BACKEND_ACTIVE_PATH}" "${STATE_RESOURCE_GROUP_NAME}" "${STORAGE_ACCOUNT_NAME}" "${CONTAINER_NAME}" "${STATE_KEY}"
import pathlib
import sys

template_path, output_path, resource_group, storage_account, container_name, key = sys.argv[1:7]
content = pathlib.Path(template_path).read_text(encoding="utf-8")
content = content.replace("__AZURE_STATE_RESOURCE_GROUP__", resource_group)
content = content.replace("__AZURE_STATE_STORAGE_ACCOUNT__", storage_account)
content = content.replace("__AZURE_STATE_CONTAINER__", container_name)
content = content.replace("__AZURE_STATE_KEY__", key)
pathlib.Path(output_path).write_text(content, encoding="utf-8")
PY
else
  echo "Azure account bootstrap completed without switching Terraform backend."
  echo "Leaving ${BACKEND_ACTIVE_PATH} untouched because clouds.control_plane=${CONTROL_PLANE}."
fi

LOCAL_TERRAFORM_TFVARS="${REPO_ROOT}/terraform/local.generated.auto.tfvars.json"
echo "Writing local Terraform config at ${LOCAL_TERRAFORM_TFVARS}..."
cat > "${LOCAL_TERRAFORM_TFVARS}" <<EOF
{
  "ssh_public_key_path": "${SSH_PUBLIC_KEY_PATH}",
  "azure_subscription_id": "${SUBSCRIPTION_ID}",
  "azure_tenant_id": "${TENANT_ID}",
  "azure_location": "${LOCATION}"
}
EOF

LOCAL_ANSIBLE_CONFIG="${REPO_ROOT}/ansible/vars/local.generated.json"
echo "Writing local Ansible config at ${LOCAL_ANSIBLE_CONFIG}..."
cat > "${LOCAL_ANSIBLE_CONFIG}" <<EOF
{
  "azure_subscription_id": "${SUBSCRIPTION_ID}",
  "azure_tenant_id": "${TENANT_ID}",
  "azure_resource_group_name": "${RESOURCE_GROUP_NAME}",
  "azure_key_vault_name": "${KEY_VAULT_NAME}"
}
EOF

mkdir -p "${REPO_ROOT}/local"
echo "Writing generated Azure env at ${GENERATED_AZURE_ENV_PATH}..."
cat > "${GENERATED_AZURE_ENV_PATH}" <<EOF
#!/bin/bash
export ARM_CLIENT_ID="${CLIENT_ID}"
export ARM_CLIENT_SECRET="${CLIENT_SECRET}"
export ARM_TENANT_ID="${TENANT_ID}"
export ARM_SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
export ANSIBLE_CONFIG="${REPO_ROOT}/ansible.cfg"
export AZURE_SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
export AZURE_TENANT_ID="${TENANT_ID}"
export AZURE_RESOURCE_GROUP="${RESOURCE_GROUP_NAME}"
export AZURE_KEYVAULT_NAME="${KEY_VAULT_NAME}"
export AZURE_KEYVAULT_URL="https://${KEY_VAULT_NAME}.vault.azure.net/"
export TF_VAR_azure_subscription_id="${SUBSCRIPTION_ID}"
export TF_VAR_azure_tenant_id="${TENANT_ID}"
export TF_VAR_azure_location="${LOCATION}"
export COINOPS_REPO_ROOT="${REPO_ROOT}"
export SSH_KEY_PATH="\${HOME}/.ssh/ssh-key-coin-ops"
EOF
chmod 600 "${GENERATED_AZURE_ENV_PATH}"
if [[ "${ACTIVATE_BACKEND}" == "true" ]]; then
  cp "${GENERATED_AZURE_ENV_PATH}" "${GENERATED_ACTIVE_ENV_PATH}"
  chmod 600 "${GENERATED_ACTIVE_ENV_PATH}"
fi

BOOTSTRAP_TFVARS="${REPO_ROOT}/terraform/bootstrap.secrets.auto.tfvars"
if [ ! -f "${BOOTSTRAP_TFVARS}" ]; then
  echo "Writing bootstrap secrets template at ${BOOTSTRAP_TFVARS}..."
  cat > "${BOOTSTRAP_TFVARS}" <<EOF
db_password          = "not_serious_just_a_placeholder"
rabbitmq_password    = "not_serious_just_a_placeholder"
ghcr_token           = "not_serious_just_a_placeholder"
cloudflare_api_token = "not_serious_just_a_placeholder"
EOF
fi

echo "Bootstrap completed successfully."
if [[ "${ACTIVATE_BACKEND}" == "true" ]]; then
  echo "Next steps:"
  echo "  1. Source ${GENERATED_AZURE_ENV_PATH} (or local/generated-env.sh)"
  echo "  2. Edit terraform/bootstrap.secrets.auto.tfvars if you need to seed/rotate secrets"
  echo "  3. Review terraform/backend.active.tf and terraform/local.generated.auto.tfvars.json"
  echo "  4. cd ${REPO_ROOT}/terraform && terraform init -reconfigure && terraform apply"
else
  echo "Next steps:"
  echo "  1. Keep using the existing control-plane backend env for Terraform state."
  echo "  2. Source ${GENERATED_AZURE_ENV_PATH} in the same shell to add Azure auth/runtime settings."
  echo "  3. Edit terraform/bootstrap.secrets.auto.tfvars if you want to seed Azure Key Vault."
  echo "  4. Run terraform init -reconfigure only against the current control-plane backend."
fi
