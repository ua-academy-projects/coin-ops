#!/usr/bin/env bash
# =============================================================================
# GCP Bootstrap Script for Terraform
# =============================================================================
# Creates:
#   - GCP Project (or uses existing)
#   - Service Account with least-privilege IAM roles
#   - GCS bucket for Terraform remote state
#   - Local .env file for Terraform (NOT committed to Git)
#
# Usage:
#   chmod +x bootstrap.sh
#   ./bootstrap.sh
# =============================================================================

set -euo pipefail

# ─── Color output ─────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log()    { echo -e "${GREEN}[✓]${NC} $*"; }
info()   { echo -e "${CYAN}[i]${NC} $*"; }
warn()   { echo -e "${YELLOW}[!]${NC} $*"; }
error()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }
header() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"; echo -e "${BOLD}${CYAN}  $*${NC}"; echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}"; }

# ─── Configuration ────────────────────────────────────────────────────────────
# Edit these values before running the script
BILLING_ACCOUNT="019FE5-FDDED3-4DA1A0"              
PROJECT_ID="${PROJECT_ID:-}"   
REGION="${REGION:-us-central1}"

# Auto-generate project ID if not set (GCP project IDs must be globally unique)
if [[ -z "$PROJECT_ID" ]]; then
  RANDOM_SUFFIX=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 6)
  PROJECT_ID="tf-bootstrap-${RANDOM_SUFFIX}"
fi

SA_NAME="terraform-sa"
SA_DISPLAY_NAME="Terraform Service Account"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
STATE_BUCKET="${PROJECT_ID}-tf-state"
KEY_FILE="./sa-key.json"
ENV_FILE="./.env.terraform"

# ─── Prerequisite check ───────────────────────────────────────────────────────
header "Checking Prerequisites"

command -v gcloud >/dev/null 2>&1 || error "gcloud CLI not found. Install: https://cloud.google.com/sdk/docs/install"
command -v terraform >/dev/null 2>&1 || error "terraform not found. Install: https://developer.hashicorp.com/terraform/downloads"

info "gcloud version: $(gcloud version --format='value(Google Cloud SDK)' 2>/dev/null | head -1)"
info "terraform version: $(terraform version -json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["terraform_version"])' 2>/dev/null || terraform version | head -1)"

# Check gcloud auth
ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | head -1)
if [[ -z "$ACTIVE_ACCOUNT" ]]; then
  warn "No active gcloud account. Running 'gcloud auth login'..."
  gcloud auth login
else
  log "Authenticated as: ${ACTIVE_ACCOUNT}"
fi

# ─── Project setup ────────────────────────────────────────────────────────────
header "Setting Up GCP Project"

# Check if project already exists
if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
  warn "Project '${PROJECT_ID}' already exists. Reusing it."
else
  info "Creating project: ${PROJECT_ID}"
  gcloud projects create "$PROJECT_ID" \
    --name="TF Bootstrap Project" \
    --labels="managed-by=bootstrap-script,purpose=terraform-learning"
  log "Project created: ${PROJECT_ID}"
fi

# Set active project
gcloud config set project "$PROJECT_ID"
log "Active project set to: ${PROJECT_ID}"

# Link billing account if provided
if [[ -n "$BILLING_ACCOUNT" ]]; then
  info "Linking billing account: ${BILLING_ACCOUNT}"
  gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT"
  log "Billing linked"
else
  warn "BILLING_ACCOUNT not set. Skipping billing link."
  warn "If APIs fail to enable, you may need to link billing manually:"
  warn "  gcloud billing projects link ${PROJECT_ID} --billing-account=XXXXX-XXXXX-XXXXX"
fi

# ─── Enable required APIs ─────────────────────────────────────────────────────
header "Enabling Required GCP APIs"

APIS=(
  "cloudresourcemanager.googleapis.com"  # Required for IAM operations
  "iam.googleapis.com"                   # Service Account management
  "storage.googleapis.com"               # GCS for Terraform state
  "compute.googleapis.com"               # Compute Engine (for test resource)
)

for api in "${APIS[@]}"; do
  info "Enabling: ${api}"
  gcloud services enable "$api" --project="$PROJECT_ID"
done
log "All required APIs enabled"

# ─── Service Account ─────────────────────────────────────────────────────────
header "Creating Service Account"

if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" &>/dev/null; then
  warn "Service account '${SA_EMAIL}' already exists. Reusing it."
else
  gcloud iam service-accounts create "$SA_NAME" \
    --display-name="$SA_DISPLAY_NAME" \
    --description="Terraform automation SA - created by bootstrap.sh" \
    --project="$PROJECT_ID"
  log "Service Account created: ${SA_EMAIL}"
  info "Waiting for SA to propagate..."
  sleep 15
fi

# ─── IAM Roles (Least Privilege) ─────────────────────────────────────────────
header "Assigning Minimal IAM Roles"

# Roles explanation:
#   storage.objectAdmin  → read/write Terraform state in GCS bucket
#   compute.networkAdmin → create VPC networks (our test resource)
#   iam.serviceAccountUser → allows running as this SA (impersonation)
#
# NOT granted: owner, editor, project-wide admin — not needed for our scope

ROLES=(
  "roles/storage.objectAdmin"        # Full access to GCS objects (state bucket)
  "roles/compute.networkAdmin"       # Create/manage VPC networks
  "roles/iam.serviceAccountUser"     # Allows Terraform to use this SA
)

for role in "${ROLES[@]}"; do
  info "Binding role: ${role}"
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="$role" \
    --quiet
done
log "IAM roles assigned (least privilege)"

# ─── GCS Bucket for Terraform State ──────────────────────────────────────────
header "Creating GCS State Bucket"

if gsutil ls "gs://${STATE_BUCKET}" &>/dev/null; then
  warn "Bucket 'gs://${STATE_BUCKET}' already exists. Reusing it."
else
  gsutil mb \
    -p "$PROJECT_ID" \
    -l "$REGION" \
    -b on \
    "gs://${STATE_BUCKET}"
  log "Bucket created: gs://${STATE_BUCKET}"
fi

# Enable versioning — allows recovery of previous state files
gsutil versioning set on "gs://${STATE_BUCKET}"
log "Versioning enabled on state bucket"

# Prevent public access (state may contain sensitive values)
gsutil uniformbucketlevelaccess set on "gs://${STATE_BUCKET}"
log "Uniform bucket-level access enabled (no public access)"

# ─── Service Account Key ─────────────────────────────────────────────────────
header "Generating Service Account Key"

if [[ -f "$KEY_FILE" ]]; then
  warn "Key file '${KEY_FILE}' already exists. Skipping key creation."
  warn "Delete it manually and re-run if you need a fresh key."
else
  gcloud iam service-accounts keys create "$KEY_FILE" \
    --iam-account="$SA_EMAIL" \
    --project="$PROJECT_ID"
  log "SA key written to: ${KEY_FILE}"
  warn "⚠ NEVER commit ${KEY_FILE} to Git! It is already in .gitignore."
fi

# ─── Write .env.terraform ─────────────────────────────────────────────────────
header "Writing .env.terraform"

cat > "$ENV_FILE" <<EOF
# ============================================================
# Terraform environment config — generated by bootstrap.sh
# DO NOT commit this file to Git!
# Source before running Terraform: source .env.terraform
# ============================================================

export TF_VAR_project_id="${PROJECT_ID}"
export TF_VAR_region="${REGION}"
export TF_VAR_state_bucket="${STATE_BUCKET}"

# Tell Terraform to authenticate as the Service Account
export GOOGLE_APPLICATION_CREDENTIALS="$(realpath "$KEY_FILE")"

# Convenience alias
export GCP_SA_EMAIL="${SA_EMAIL}"
EOF

log "Environment file written: ${ENV_FILE}"
warn "⚠ Source it before running Terraform: source ${ENV_FILE}"

# ─── Summary ─────────────────────────────────────────────────────────────────
header "Bootstrap Complete"

echo ""
echo -e "  ${BOLD}Project ID:${NC}     ${PROJECT_ID}"
echo -e "  ${BOLD}Service Account:${NC} ${SA_EMAIL}"
echo -e "  ${BOLD}State Bucket:${NC}   gs://${STATE_BUCKET}"
echo -e "  ${BOLD}SA Key File:${NC}    ${KEY_FILE}"
echo -e "  ${BOLD}Env File:${NC}       ${ENV_FILE}"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo -e "  1. source ${ENV_FILE}"
echo -e "  2. cd terraform/"
echo -e "  3. terraform init"
echo -e "  4. terraform plan"
echo -e "  5. terraform apply"
echo ""
