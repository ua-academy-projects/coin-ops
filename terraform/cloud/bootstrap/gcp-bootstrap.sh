#!/usr/bin/env bash
# GCP Bootstrap Script
# Purpose: Prepare a project for infrastructure provisioning
# Steps:
#   1) Validate required tools and active gcloud login
#   2) Create or reuse a GCP project
#   3) Link a billing account
#   4) Enable required APIs
#   5) Create a Terraform service account
#   6) Assign required IAM roles
#   7) Create backend storage for Terraform state
#   8) Create a service account key
#   9) Create an environment file
#
# Usage:
#   1. Export the required variables before running
#   2. chmod +x gcp-bootstrap.sh
#   3. gcloud auth login
#   4. ./gcp-bootstrap.sh

set -euo pipefail
# -e -> exit on error
# -u -> exit on unset variable
# -o pipefail -> exit on pipe failure

# ------------------------------------------------------------
# Variables
# ------------------------------------------------------------
# Environment-specific inputs.
PROJECT_ID="${PROJECT_ID}"
REGION="${REGION}"
BILLING_ACCOUNT="${BILLING_ACCOUNT}"

# Stable bootstrap defaults.
SA_NAME="${SA_NAME:-coin-ops-terraform}"
BUCKET_NAME="${BUCKET_NAME:-${PROJECT_ID}-tfstate}"
KEY_FILE="${KEY_FILE:-./terraform-sa-key.json}"
ENV_FILE="${ENV_FILE:-./terraform.env}"
SECRET_PLACEHOLDER_VALUE="${SECRET_PLACEHOLDER_VALUE:-CHANGE_ME_IN_SECRET_MANAGER}"

SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

REQUIRED_SECRETS=(
  "ghcr-username"
  "ghcr-token"
  "rabbitmq-password"
  "db-password"
)

SA_ROLES=(
  "roles/editor"                           # create and manage most resources
  "roles/iam.serviceAccountAdmin"          # manage service accounts
  "roles/resourcemanager.projectIamAdmin"  # manage IAM bindings on the project
  "roles/storage.admin"                    # full access to GCS (needed for state bucket)
)

# ------------------------------------------------------------
# Validate required variables
# ------------------------------------------------------------
for var in \
  PROJECT_ID \
  REGION \
  BILLING_ACCOUNT; do
  if [[ -z "${!var}" ]]; then
    echo "ERROR: $var is not set. Export it before running."
    exit 1
  fi
done

if [[ ${#REQUIRED_SECRETS[@]} -eq 0 ]]; then
  echo "ERROR: REQUIRED_SECRETS is empty. Add at least one secret name."
  exit 1
fi

# ------------------------------------------------------------
# 1) Check required tools and active login
# ------------------------------------------------------------
echo ""
echo "==> Step 1: Tooling and Login"
if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud is not installed"
  exit 1
fi

ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' | head -n1 || true)"
if [[ -z "${ACTIVE_ACCOUNT}" ]]; then
  echo "No active gcloud account found. Run: gcloud auth login"
  exit 1
fi
echo "Logged in as: ${ACTIVE_ACCOUNT}"

# ------------------------------------------------------------
# 2) Create or reuse project
# ------------------------------------------------------------
echo ""
echo "==> Step 2: Project"
if gcloud projects describe "${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Project ${PROJECT_ID} already exists, skipping"
else
  echo "Creating project ${PROJECT_ID}..."
  gcloud projects create "${PROJECT_ID}"
fi

# ------------------------------------------------------------
# 3) Link billing account
# ------------------------------------------------------------
echo ""
echo "==> Step 3: Billing"
echo "Linking billing account..."
gcloud billing projects link "${PROJECT_ID}" \
  --billing-account="${BILLING_ACCOUNT}"

gcloud config set project "${PROJECT_ID}" >/dev/null
gcloud auth application-default set-quota-project "${PROJECT_ID}" >/dev/null 2>&1 || true

# ------------------------------------------------------------
# 4) Enable required APIs
# ------------------------------------------------------------
echo ""
echo "==> Step 4: APIs"
echo "Enabling APIs..."
# cloudresourcemanager - manage GCP projects and resources
# iam                  - manage IAM roles and policies
# iamcredentials       - generate short-lived credentials for SA
# serviceusage         - enable/disable GCP APIs
# storage              - GCS (used for terraform state bucket)
# compute              - manage compute resources (VMs, networks etc)
# secretmanager        - store deployment secrets for VMs
gcloud services enable \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  serviceusage.googleapis.com \
  storage.googleapis.com \
  compute.googleapis.com \
  secretmanager.googleapis.com \
  --project="${PROJECT_ID}"

# ------------------------------------------------------------
# 5) Create service account
# ------------------------------------------------------------
echo ""
echo "==> Step 5: Service Account"
if gcloud iam service-accounts describe "${SA_EMAIL}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  echo "Service account ${SA_EMAIL} already exists, skipping"
else
  echo "Creating service account ${SA_EMAIL}..."
  gcloud iam service-accounts create "${SA_NAME}" \
    --display-name="Terraform Service Account" \
    --project="${PROJECT_ID}"
fi

# ------------------------------------------------------------
# 6) Assign IAM roles
# ------------------------------------------------------------
echo ""
echo "==> Step 6: IAM Roles"
echo "Assigning IAM roles..."
for ROLE in "${SA_ROLES[@]}"; do
  echo "  ${ROLE}"
  gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="${ROLE}" \
    --condition=None \
    --quiet >/dev/null
done

# ------------------------------------------------------------
# 7) Create state bucket
# ------------------------------------------------------------
echo ""
echo "==> Step 7: State Bucket"
if gsutil ls -b "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  echo "Bucket gs://${BUCKET_NAME} already exists, skipping"
else
  echo "Creating bucket gs://${BUCKET_NAME}..."
  gsutil mb -p "${PROJECT_ID}" -l "${REGION}" -b on "gs://${BUCKET_NAME}"
fi

# Enable bucket versioning for safer Terraform state recovery.
gsutil versioning set on "gs://${BUCKET_NAME}" >/dev/null
# Allow the Terraform service account to manage objects in the state bucket.
gsutil iam ch \
  "serviceAccount:${SA_EMAIL}:roles/storage.objectAdmin" \
  "gs://${BUCKET_NAME}" >/dev/null

# ------------------------------------------------------------
# 8) Create service account key
# ------------------------------------------------------------
echo ""
echo "==> Step 8: Service Account Key"
if [[ -f "${KEY_FILE}" ]]; then
  echo "Key file ${KEY_FILE} already exists, skipping"
else
  echo "Creating key file ${KEY_FILE}..."
  gcloud iam service-accounts keys create "${KEY_FILE}" \
    --iam-account="${SA_EMAIL}" \
    --project="${PROJECT_ID}"
  chmod 600 "${KEY_FILE}"
fi

# ------------------------------------------------------------
# 9) Create required secrets
# ------------------------------------------------------------
echo ""
echo "==> Step 9: Secret Manager"
echo "Ensuring Secret Manager secrets exist..."
for SECRET_NAME in "${REQUIRED_SECRETS[@]}"; do
  if gcloud secrets describe "${SECRET_NAME}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
    echo "Secret already exists: ${SECRET_NAME}"
  else
    echo "Creating secret ${SECRET_NAME}..."
    gcloud secrets create "${SECRET_NAME}" \
      --replication-policy="automatic" \
      --project="${PROJECT_ID}" >/dev/null

    printf "%s" "${SECRET_PLACEHOLDER_VALUE}" | gcloud secrets versions add "${SECRET_NAME}" \
      --data-file=- \
      --project="${PROJECT_ID}" >/dev/null

    echo "Secret created with placeholder value: ${SECRET_NAME}"
  fi
done

echo ""
echo "WARNING: Required secrets now exist in Secret Manager, but may still contain the bootstrap placeholder."
echo "WARNING: Replace placeholder values for:"
for SECRET_NAME in "${REQUIRED_SECRETS[@]}"; do
  echo " - ${SECRET_NAME}"
done

# ------------------------------------------------------------
# 10) Create environment file
# ------------------------------------------------------------
echo ""
echo "==> Step 10: Environment File"
echo "Writing ${ENV_FILE}..."
ABS_KEY_PATH="$(realpath "${KEY_FILE}")"

cat > "${ENV_FILE}" <<EOF
export GOOGLE_APPLICATION_CREDENTIALS="${ABS_KEY_PATH}"
export GOOGLE_PROJECT="${PROJECT_ID}"
export GOOGLE_REGION="${REGION}"

export TF_VAR_project_id="${PROJECT_ID}"
export TF_VAR_region="${REGION}"
export TF_VAR_service_account_email="${SA_EMAIL}"

export TF_STATE_BUCKET="${BUCKET_NAME}"
EOF
chmod 600 "${ENV_FILE}"

printf "\nDone!\n"
printf "  %-20s %s\n" "Project:"         "${PROJECT_ID}"
printf "  %-20s %s\n" "Service account:" "${SA_EMAIL}"
printf "  %-20s %s\n" "State storage:"   "gs://${BUCKET_NAME}"
printf "  %-20s %s\n" "Key file:"        "${ABS_KEY_PATH}"
printf "  %-20s %s\n" "Env file:"        "${ENV_FILE}"
printf "\nNext steps:\n"
printf "  update placeholder secrets in Secret Manager\n"
printf "  source %s\n" "${ENV_FILE}"
printf "  terraform init\n"
