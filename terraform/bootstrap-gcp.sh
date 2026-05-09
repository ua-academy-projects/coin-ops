#!/bin/bash

# Bootstrap script to set up GCP environment for Terraform
# Before running this script, ensure your organization's policy allows Service Account key creation.
# You may need to disable the "iam.disableServiceAccountKeyCreation" policy constraint for your organization.

# Configuration variables - edit before running
PROJECT_ID="project-6f41102f-c77c-46a3-aac"
SA_NAME="terraform-sa"
BUCKET_NAME="internship-state-bucket"
REGION="europe-central2"

# Absolute path to THIS repo
REPO_ROOT="/mnt/d/Internship/coin-ops-local/coin-ops"

# SA key is stored inside the repo under terraform/ (gitignored)
SA_KEY_PATH="${REPO_ROOT}/terraform/sa-key.json"
SSH_PUBLIC_KEY_PATH="${HOME}/.ssh/ssh-key-coin-ops.pub"
GENERATED_ENV_PATH="${REPO_ROOT}/local/generated-env.sh"

# Non-secret local runtime defaults generated for Terraform/Ansible
APP_DOMAIN="coinops-d.pp.ua"
TLS_MODE="certbot"
RUNTIME_BACKEND="external"
GHCR_USERNAME="hrenchevskyi-d"
IMAGE_REGISTRY="ghcr.io/ua-academy-projects"
IMAGE_TAG="shabat-latest"
CERTBOT_EMAIL_LOCALPART="admin"
PROXY_PORT=8080
HISTORY_PORT=8000

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

# Disable Policy to allow Service Account key creation
gcloud resource-manager org-policies disable-enforce iam.disableServiceAccountKeyCreation \
    --project=$PROJECT_ID

# Enable required GCP APIs
echo "Enabling required APIs..."
gcloud services enable iamcredentials.googleapis.com --account="$BOOTSTRAP_ACCOUNT" > /dev/null
gcloud services enable iam.googleapis.com --account="$BOOTSTRAP_ACCOUNT" > /dev/null
gcloud services enable compute.googleapis.com --account="$BOOTSTRAP_ACCOUNT" > /dev/null

# Create Service Account
echo "Creating Service Account: $SA_NAME"
gcloud iam service-accounts create "$SA_NAME" \
    --account="$BOOTSTRAP_ACCOUNT" \
    --display-name="Terraform Service Account"

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
echo "Creating GCS bucket: $BUCKET_NAME"
gcloud storage buckets create "gs://$BUCKET_NAME" --location="$REGION" --account="$BOOTSTRAP_ACCOUNT"

# Enable object versioning for state protection
echo "Enabling bucket versioning..."
gcloud storage buckets update "gs://$BUCKET_NAME" --versioning --account="$BOOTSTRAP_ACCOUNT"

# Generate Service Account key into terraform/
echo "Generating JSON key at ${SA_KEY_PATH}..."
gcloud iam service-accounts keys create "$SA_KEY_PATH" \
    --account="$BOOTSTRAP_ACCOUNT" \
    --iam-account="$SA_EMAIL"

# Create a gitignored local non-secret config for Terraform.
LOCAL_TERRAFORM_TFVARS="${REPO_ROOT}/terraform/local.generated.auto.tfvars.json"
echo "Writing local Terraform config at ${LOCAL_TERRAFORM_TFVARS}..."
cat > "$LOCAL_TERRAFORM_TFVARS" << EOF
{
  "gcp_project_id": "${PROJECT_ID}",
  "gcp_region": "${REGION}",
  "ssh_public_key_path": "${SSH_PUBLIC_KEY_PATH}",
  "app_domain": "${APP_DOMAIN}",
  "cloudflare_zone_id": "de9eabb2b5b0b9b25b7ee2decc5d161b"
}
EOF

# Create a gitignored local non-secret config for Ansible derived from the same bootstrap source.
LOCAL_ANSIBLE_CONFIG="${REPO_ROOT}/ansible/vars/local.generated.json"
echo "Writing local Ansible config at ${LOCAL_ANSIBLE_CONFIG}..."
cat > "$LOCAL_ANSIBLE_CONFIG" << EOF
{
  "gcp_project": "${PROJECT_ID}",
  "runtime_backend": "${RUNTIME_BACKEND}",
  "app_domain": "${APP_DOMAIN}",
  "tls_mode": "${TLS_MODE}",
  "certbot_email_localpart": "${CERTBOT_EMAIL_LOCALPART}",
  "image_registry": "${IMAGE_REGISTRY}",
  "image_tag": "${IMAGE_TAG}",
  "registry_username": "${GHCR_USERNAME}",
  "proxy_port": ${PROXY_PORT},
  "history_port": ${HISTORY_PORT}
}
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
export SSH_KEY_PATH="\${HOME}/.ssh/ssh-key-coin-ops"
export GHCR_USERNAME="${GHCR_USERNAME}"
export APP_DOMAIN="${APP_DOMAIN}"
export TLS_MODE="${TLS_MODE}"
export CERTBOT_EMAIL="${CERTBOT_EMAIL_LOCALPART}@${APP_DOMAIN}"
export RUNTIME_BACKEND="${RUNTIME_BACKEND}"
EOF
chmod 600 "$GENERATED_ENV_PATH"

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
echo "  3. Source local/generated-env.sh or add it to your ~/.bashrc"
echo "  4. Seed Secret Manager and infra: cd ${REPO_ROOT}/terraform && terraform init && terraform apply -var='seed_secret_manager=true'"
echo "  5. Normal terraform/ansible runs can reuse the generated local env + local config files"
