#!/bin/bash

# Bootstrap script to set up GCP environment for Terraform
# Before running this script, ensure your organization's policy allows Service Account key creation.
# You may need to disable the "iam.disableServiceAccountKeyCreation" policy constraint for your organization.

# Configuration variables — edit before running
PROJECT_ID="project-6f41102f-c77c-46a3-aac"   # GCP project ID
SA_NAME="terraform-sa"
BUCKET_NAME="internship-state-bucket"
REGION="europe-central2"

# Absolute path to THIS repo (used to build ANSIBLE_CONFIG)
REPO_ROOT="/mnt/d/Internship/coin-ops-local/coin-ops"

# SA key is stored inside the repo under terraform/ (gitignored)
SA_KEY_PATH="${REPO_ROOT}/terraform/sa-key.json"

echo "Starting bootstrap process for project: $PROJECT_ID"

# Set default GCP project
gcloud config set project "$PROJECT_ID"

# Disable Policy to allow Service Account key creation
gcloud resource-manager org-policies disable-enforce iam.disableServiceAccountKeyCreation \
    --project=$PROJECT_ID
# sleep 180 # Wait for policy change to propagate

# Enable required GCP APIs
echo "Enabling required APIs..."
gcloud services enable iamcredentials.googleapis.com > /dev/null
gcloud services enable iam.googleapis.com > /dev/null
gcloud services enable compute.googleapis.com > /dev/null

# Create Service Account
echo "Creating Service Account: $SA_NAME"
gcloud iam service-accounts create "$SA_NAME" \
    --display-name="Terraform Service Account"

SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Assign IAM bindings
echo "Assigning IAM roles..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/storage.admin" \
    --condition=None > /dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/compute.networkAdmin" \
    --condition=None > /dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/compute.instanceAdmin.v1" \
    --condition=None > /dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/iam.serviceAccountUser" \
    --condition=None > /dev/null

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="roles/compute.securityAdmin"

# Create GCS Bucket for Terraform remote state
echo "Creating GCS bucket: $BUCKET_NAME"
gcloud storage buckets create "gs://$BUCKET_NAME" --location="$REGION"

# Enable object versioning for state protection
echo "Enabling bucket versioning..."
gcloud storage buckets update "gs://$BUCKET_NAME" --versioning

# Generate Service Account key into terraform/
echo "Generating JSON key at ${SA_KEY_PATH}..."
gcloud iam service-accounts keys create "$SA_KEY_PATH" \
    --iam-account="$SA_EMAIL"

# Write complete .env covering Terraform + Ansible + inventory plugins.
# Ansible-specific secrets (DB_PASSWORD, GHCR_TOKEN, etc.) must be filled in manually.
echo "Writing .env..."
cat > .env << EOF
# ── GCP credentials and configuration ────────────────────────────────
export GOOGLE_APPLICATION_CREDENTIALS="${SA_KEY_PATH}"
export TF_VAR_gcp_project_id="${PROJECT_ID}"
export TF_VAR_gcp_region="${REGION}"

# ── SSH key (shared by Terraform and Ansible) ─────────────────────────
export SSH_KEY_PATH="\${HOME}/.ssh/ssh-key-coin-ops"
export TF_VAR_ssh_public_key_path="\${SSH_KEY_PATH}.pub"

# ── Ansible: cloud-native inventory plugin mappings ───────────────────
export GOOGLE_CLOUD_PROJECT=\$TF_VAR_gcp_project_id
export GCP_PROJECT=\$TF_VAR_gcp_project_id
export GCP_SERVICE_ACCOUNT_FILE=\$GOOGLE_APPLICATION_CREDENTIALS
export GCP_REGION=\$TF_VAR_gcp_region

# ── Ansible: config (absolute path — safe when .env is sourced from anywhere) ──
export ANSIBLE_CONFIG="${REPO_ROOT}/ansible.cfg"

# ── Ansible: application secrets — FILL IN BEFORE FIRST DEPLOY ───────
export DB_PASSWORD="CHANGE_ME"
export RABBITMQ_PASSWORD="CHANGE_ME"
export RUNTIME_BACKEND="external"
export APP_DOMAIN="CHANGE_ME"        # public IP of app-1 or real domain
export TLS_MODE="selfsigned"
export GHCR_USERNAME="CHANGE_ME"     # GitHub username
export GHCR_TOKEN="CHANGE_ME"        # GitHub PAT with read:packages
EOF

echo "Bootstrap completed successfully."
echo "Next steps:"
echo "  1. Edit .env — fill in DB_PASSWORD, RABBITMQ_PASSWORD, GHCR_USERNAME, GHCR_TOKEN, APP_DOMAIN"
echo "  2. Run: source .env"
echo "  3. cd ${REPO_ROOT}/terraform && terraform init && terraform apply"
