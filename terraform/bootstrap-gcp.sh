#!/bin/bash
set -euo pipefail

# Bootstrap script to set up GCP environment for Terraform
# Before running this script, ensure your organization's policy allows Service Account key creation.
# You may need to disable the "iam.disableServiceAccountKeyCreation" policy constraint for your organization.

# Configuration sources
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MAPPING_PATH="${SCRIPT_DIR}/config/cloud_mappings.json"
CONFIG_DIR="${SCRIPT_DIR}/config"
BACKEND_TEMPLATE_PATH="${SCRIPT_DIR}/backends/backend.gcp.tf.tmpl"
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

PROJECT_ID="$(read_config 'data["clouds"]["providers"]["gcp"]["account"]["project_id"]')"
SA_NAME="$(read_config 'data["clouds"]["providers"]["gcp"]["terraform_identity"]["name"]')"
BUCKET_NAME="$(read_config 'data["clouds"]["backends"]["gcp"]["bucket"]')"
STATE_PREFIX="$(read_config 'data["clouds"]["backends"]["gcp"].get("prefix", "infra/state")')"
REGION_PROFILE="$(read_config 'data["general"]["region_profile"]')"
REGION="$(python3 -c 'import json,sys; data=json.load(open(sys.argv[1], encoding="utf-8")); print(data["regions"]["gcp"][sys.argv[2]]["region"])' "${MAPPING_PATH}" "${REGION_PROFILE}")"

# SA key is stored inside the repo under terraform/ (gitignored)
SA_KEY_PATH="${REPO_ROOT}/terraform/sa-key.json"
SSH_PUBLIC_KEY_PATH="${HOME}/.ssh/ssh-key-coin-ops.pub"
GENERATED_ENV_PATH="${REPO_ROOT}/local/generated-gcp-env.sh"
GENERATED_ACTIVE_ENV_PATH="${REPO_ROOT}/local/generated-env.sh"

BOOTSTRAP_ACCOUNT="${BOOTSTRAP_ACCOUNT:-$(gcloud config get-value account 2>/dev/null)}"

echo "Starting bootstrap process for project: $PROJECT_ID"

if [ -z "$BOOTSTRAP_ACCOUNT" ]; then
  echo "No active gcloud account found. Run 'gcloud auth login' with a human/operator account first."
  exit 1
fi

if [[ "$BOOTSTRAP_ACCOUNT" == "${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" ]]; then
  echo "Bootstrap cannot run while the active gcloud account is the terraform service account."
  echo "Run 'gcloud auth login' with a human/operator account, then re-run this script."
  exit 1
fi

# Set default GCP project
gcloud config set project "$PROJECT_ID" --account="$BOOTSTRAP_ACCOUNT"

# Disable policy to allow Service Account key creation when the operator has
# permission to do so. Some projects do not expose this policy at project scope;
# in that case the later key creation command gives the actionable failure.
if ! gcloud resource-manager org-policies disable-enforce iam.disableServiceAccountKeyCreation \
    --project="$PROJECT_ID" > /dev/null 2>&1; then
  echo "Warning: could not disable iam.disableServiceAccountKeyCreation at project scope."
  echo "Continuing; service-account key creation will fail later if the org policy is enforced."
fi

# Enable required GCP APIs
echo "Enabling required APIs..."
gcloud services enable iamcredentials.googleapis.com --account="$BOOTSTRAP_ACCOUNT" > /dev/null
gcloud services enable iam.googleapis.com --account="$BOOTSTRAP_ACCOUNT" > /dev/null
gcloud services enable cloudresourcemanager.googleapis.com --account="$BOOTSTRAP_ACCOUNT" > /dev/null
gcloud services enable compute.googleapis.com --account="$BOOTSTRAP_ACCOUNT" > /dev/null
gcloud services enable servicenetworking.googleapis.com --account="$BOOTSTRAP_ACCOUNT" > /dev/null
gcloud services enable sqladmin.googleapis.com --account="$BOOTSTRAP_ACCOUNT" > /dev/null
gcloud services enable secretmanager.googleapis.com --account="$BOOTSTRAP_ACCOUNT" > /dev/null
gcloud services enable storage.googleapis.com --account="$BOOTSTRAP_ACCOUNT" > /dev/null

# Create Service Account
echo "Ensuring Service Account exists: $SA_NAME"
if ! gcloud iam service-accounts describe "${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com" --account="$BOOTSTRAP_ACCOUNT" > /dev/null 2>&1; then
  gcloud iam service-accounts create "$SA_NAME" \
      --account="$BOOTSTRAP_ACCOUNT" \
      --display-name="Terraform Service Account"
fi

SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Assign IAM bindings
echo "Assigning IAM roles..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --account="$BOOTSTRAP_ACCOUNT" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/storage.admin" \
    --condition=None > /dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --account="$BOOTSTRAP_ACCOUNT" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/compute.networkAdmin" \
    --condition=None > /dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --account="$BOOTSTRAP_ACCOUNT" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/compute.instanceAdmin.v1" \
    --condition=None > /dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --account="$BOOTSTRAP_ACCOUNT" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/iam.serviceAccountUser" \
    --condition=None > /dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --account="$BOOTSTRAP_ACCOUNT" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/compute.securityAdmin"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --account="$BOOTSTRAP_ACCOUNT" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/cloudsql.admin"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --account="$BOOTSTRAP_ACCOUNT" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/secretmanager.admin"

# Create GCS Bucket for Terraform remote state
echo "Ensuring GCS state bucket exists: $BUCKET_NAME"
if ! gcloud storage buckets describe "gs://$BUCKET_NAME" --account="$BOOTSTRAP_ACCOUNT" > /dev/null 2>&1; then
  gcloud storage buckets create "gs://$BUCKET_NAME" --location="$REGION" --account="$BOOTSTRAP_ACCOUNT"
fi

# Enable object versioning for state protection
echo "Enabling bucket versioning..."
gcloud storage buckets update "gs://$BUCKET_NAME" --versioning --account="$BOOTSTRAP_ACCOUNT"

echo "Writing active Terraform backend at ${BACKEND_ACTIVE_PATH}..."
python3 - <<'PY' "${BACKEND_TEMPLATE_PATH}" "${BACKEND_ACTIVE_PATH}" "${BUCKET_NAME}" "${STATE_PREFIX}"
import pathlib
import sys

template_path, output_path, bucket, prefix = sys.argv[1:5]
content = pathlib.Path(template_path).read_text(encoding="utf-8")
content = content.replace("__GCP_STATE_BUCKET__", bucket)
content = content.replace("__GCP_STATE_PREFIX__", prefix)
pathlib.Path(output_path).write_text(content, encoding="utf-8")
PY

# Generate Service Account key into terraform/
echo "Generating JSON key at ${SA_KEY_PATH}..."
gcloud iam service-accounts keys create "$SA_KEY_PATH" \
    --account="$BOOTSTRAP_ACCOUNT" \
    --iam-account="$SA_EMAIL"

# Create a gitignored local Terraform config for machine-local paths.
LOCAL_TERRAFORM_TFVARS="${REPO_ROOT}/terraform/local.generated.auto.tfvars.json"
echo "Writing local Terraform config at ${LOCAL_TERRAFORM_TFVARS}..."
cat > "$LOCAL_TERRAFORM_TFVARS" << EOF
{
  "ssh_public_key_path": "${SSH_PUBLIC_KEY_PATH}"
}
EOF

# Create a gitignored optional Ansible override file. Committed JSON remains the SSOT.
LOCAL_ANSIBLE_CONFIG="${REPO_ROOT}/ansible/vars/local.generated.json"
echo "Writing local Ansible config at ${LOCAL_ANSIBLE_CONFIG}..."
cat > "$LOCAL_ANSIBLE_CONFIG" << EOF
{}
EOF

mkdir -p "${REPO_ROOT}/local"
echo "Writing generated local env at ${GENERATED_ENV_PATH}..."
cat > "$GENERATED_ENV_PATH" << EOF
#!/bin/bash
export GOOGLE_APPLICATION_CREDENTIALS="${SA_KEY_PATH}"
export ANSIBLE_CONFIG="${REPO_ROOT}/ansible.cfg"
export GOOGLE_CLOUD_PROJECT="${PROJECT_ID}"
export GOOGLE_PROJECT="${PROJECT_ID}"
export GCP_PROJECT="${PROJECT_ID}"
export CLOUDSDK_CORE_PROJECT="${PROJECT_ID}"
export COINOPS_REPO_ROOT="${REPO_ROOT}"
export SSH_KEY_PATH="\${HOME}/.ssh/ssh-key-coin-ops"
EOF
chmod 600 "$GENERATED_ENV_PATH"
cp "$GENERATED_ENV_PATH" "$GENERATED_ACTIVE_ENV_PATH"
chmod 600 "$GENERATED_ACTIVE_ENV_PATH"

# Create a gitignored bootstrap secret file for one-time Secret Manager seeding.
BOOTSTRAP_TFVARS="${REPO_ROOT}/terraform/bootstrap.secrets.auto.tfvars"
if [ ! -f "$BOOTSTRAP_TFVARS" ]; then
  echo "Writing bootstrap secrets template at ${BOOTSTRAP_TFVARS}..."
  cat > "$BOOTSTRAP_TFVARS" << EOF
db_password          = "not_serious_just_a_placeholder"
rabbitmq_password    = "not_serious_just_a_placeholder"
ghcr_token           = "not_serious_just_a_placeholder"
cloudflare_api_token = "not_serious_just_a_placeholder"
EOF
fi

echo "Bootstrap completed successfully."
echo "Next steps:"
echo "  1. Review terraform/local.generated.auto.tfvars.json and ansible/vars/local.generated.json"
echo "  2. Edit terraform/bootstrap.secrets.auto.tfvars and replace placeholder secret values"
echo "  3. Source local/generated-gcp-env.sh (or local/generated-env.sh) or add it to your ~/.bashrc"
echo "  4. Seed Secret Manager and infra: cd ${REPO_ROOT}/terraform && terraform init && terraform apply -var='seed_secret_manager=true'"
echo "  5. Normal terraform/ansible runs can reuse the generated local env + local config files"
