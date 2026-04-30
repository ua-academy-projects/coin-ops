#!/bin/bash

# ============================================================================
# Bootstrap GCP project for Terraform
# ============================================================================
# Creates a Service Account, GCS bucket for remote state, JSON key,
# .env file, and full Terraform configuration.
#
# This script is idempotent — safe to run multiple times.
# ============================================================================

set -euo pipefail

# ----------------------------------------------------------------------------
# Output colors
# ----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERR]${NC}  $1"; }

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
readonly PROJECT_ID="project-8888321c-54a9-4dac-86d"
readonly REGION="us-central1"
readonly ZONE="${REGION}-a"
readonly SA_NAME="terraform-sa"
readonly SA_DISPLAY_NAME="Terraform Service Account"
readonly SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
readonly BUCKET_NAME="tfstate-${PROJECT_ID}"
readonly NETWORK_NAME="terraform-network"
readonly VM_NAME="terraform-vm"
readonly MACHINE_TYPE="e2-micro"
readonly KEY_FILE="$(pwd)/sa-key.json"
readonly TERRAFORM_DIR="$(pwd)/terraform"

# APIs to enable
readonly APIS=(
  "cloudresourcemanager.googleapis.com"
  "iam.googleapis.com"
  "iamcredentials.googleapis.com"
  "storage.googleapis.com"
  "compute.googleapis.com"
  "serviceusage.googleapis.com"
)

# IAM roles for Service Account (least privilege)
readonly ROLES=(
  "roles/storage.admin"
  "roles/compute.networkAdmin"
  "roles/compute.instanceAdmin.v1"
  "roles/compute.securityAdmin"
  "roles/serviceusage.serviceUsageAdmin"
  "roles/iam.serviceAccountUser"
)

# ----------------------------------------------------------------------------
# Prerequisites check
# ----------------------------------------------------------------------------
check_prerequisites() {
  log_info "Checking prerequisites..."

  if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI is not installed"
    exit 1
  fi

  if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    log_error "No active gcloud authentication. Run: gcloud auth login"
    exit 1
  fi

  local current_project
  current_project=$(gcloud config get-value project 2>/dev/null || echo "")
  if [[ "$current_project" != "$PROJECT_ID" ]]; then
    log_warn "Current gcloud project: $current_project. Switching to $PROJECT_ID"
    gcloud config set project "$PROJECT_ID"
  fi

  log_success "Prerequisites OK"
}

# ----------------------------------------------------------------------------
# Enable required APIs
# ----------------------------------------------------------------------------
enable_apis() {
  log_info "Enabling required APIs..."

  for api in "${APIS[@]}"; do
    if gcloud services list --enabled --project="$PROJECT_ID" --filter="name:$api" --format="value(name)" | grep -q "$api"; then
      log_success "API already enabled: $api"
    else
      log_info "Enabling API: $api"
      gcloud services enable "$api" --project="$PROJECT_ID"
      log_success "API enabled: $api"
    fi
  done
}

# ----------------------------------------------------------------------------
# Create Service Account (idempotent)
# ----------------------------------------------------------------------------
create_service_account() {
  log_info "Checking Service Account..."

  if gcloud iam service-accounts describe "$SA_EMAIL" --project="$PROJECT_ID" &>/dev/null; then
    log_success "Service Account already exists: $SA_EMAIL"
  else
    log_info "Creating Service Account: $SA_EMAIL"
    gcloud iam service-accounts create "$SA_NAME" \
      --display-name="$SA_DISPLAY_NAME" \
      --project="$PROJECT_ID"
    log_success "Service Account created"
  fi
}

# ----------------------------------------------------------------------------
# Assign IAM roles (idempotent)
# ----------------------------------------------------------------------------
assign_iam_roles() {
  log_info "Assigning IAM roles..."

  for role in "${ROLES[@]}"; do
    if gcloud projects get-iam-policy "$PROJECT_ID" \
        --flatten="bindings[].members" \
        --format="value(bindings.role,bindings.members)" \
        | grep -q "$role	serviceAccount:$SA_EMAIL"; then
      log_success "Role already assigned: $role"
    else
      log_info "Assigning role: $role"
      gcloud projects add-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:${SA_EMAIL}" \
        --role="$role" \
        --condition=None \
        --quiet > /dev/null
      log_success "Role assigned: $role"
    fi
  done
}

# ----------------------------------------------------------------------------
# Create GCS bucket for Terraform state
# ----------------------------------------------------------------------------
create_state_bucket() {
  log_info "Checking GCS bucket for Terraform state..."

  if gcloud storage buckets describe "gs://${BUCKET_NAME}" --project="$PROJECT_ID" &>/dev/null; then
    log_success "Bucket already exists: gs://${BUCKET_NAME}"
  else
    log_info "Creating bucket: gs://${BUCKET_NAME}"
    gcloud storage buckets create "gs://${BUCKET_NAME}" \
      --project="$PROJECT_ID" \
      --location="$REGION" \
      --uniform-bucket-level-access \
      --public-access-prevention
    log_success "Bucket created"
  fi

  log_info "Ensuring versioning is enabled on bucket..."
  gcloud storage buckets update "gs://${BUCKET_NAME}" --versioning > /dev/null
  log_success "Versioning enabled"
}

# ----------------------------------------------------------------------------
# Create JSON key for Service Account
# ----------------------------------------------------------------------------
create_sa_key() {
  log_info "Checking Service Account JSON key..."

  if [[ -f "$KEY_FILE" ]]; then
    log_success "JSON key already exists: $KEY_FILE"
    log_warn "If you need a new key — delete the old one and revoke it in GCP first"
  else
    log_info "Creating JSON key: $KEY_FILE"
    gcloud iam service-accounts keys create "$KEY_FILE" \
      --iam-account="$SA_EMAIL" \
      --project="$PROJECT_ID"
    chmod 600 "$KEY_FILE"
    log_success "JSON key created (permissions 600)"
  fi
}

# ----------------------------------------------------------------------------
# Create .env file
# ----------------------------------------------------------------------------
create_env_file() {
  log_info "Creating .env file..."

  cat > .env << EOF
# Auto-generated by bootstrap.sh — DO NOT commit to Git!
export GOOGLE_APPLICATION_CREDENTIALS="${KEY_FILE}"
export GOOGLE_PROJECT="${PROJECT_ID}"
export TF_VAR_project_id="${PROJECT_ID}"
export TF_VAR_region="${REGION}"
export TF_VAR_zone="${ZONE}"
export TF_VAR_bucket_name="${BUCKET_NAME}"
EOF

  log_success ".env created"
}

# ----------------------------------------------------------------------------
# Create .gitignore
# ----------------------------------------------------------------------------
create_gitignore() {
  log_info "Creating .gitignore..."

  cat > .gitignore << 'EOF'
# Credentials — NEVER commit
sa-key.json
*-key.json
.env
.env.*

# Terraform
**/.terraform/*
*.tfstate
*.tfstate.*
*.tfvars
!*.tfvars.example
.terraform.lock.hcl
crash.log
crash.*.log
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Backup files
*.old
*.bak
EOF

  log_success ".gitignore created"
}

# ----------------------------------------------------------------------------
# Create Terraform files
# ----------------------------------------------------------------------------
create_terraform_files() {
  log_info "Creating Terraform files in $TERRAFORM_DIR..."
  mkdir -p "$TERRAFORM_DIR"

  # backend.tf — remote state location
  cat > "$TERRAFORM_DIR/backend.tf" << EOF
# Remote state stored in GCS bucket.
terraform {
  backend "gcs" {
    bucket = "${BUCKET_NAME}"
    prefix = "terraform/state"
  }
}
EOF

  # provider.tf — Terraform and provider versions
  cat > "$TERRAFORM_DIR/provider.tf" << 'EOF'
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}
EOF

  # variables.tf — variable definitions
  cat > "$TERRAFORM_DIR/variables.tf" << 'EOF'
variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP zone"
  type        = string
  default     = "us-central1-a"
}

variable "bucket_name" {
  description = "GCS bucket name for Terraform remote state"
  type        = string
}

variable "network_name" {
  description = "Name of the VPC network"
  type        = string
  default     = "terraform-network"
}

variable "vm_name" {
  description = "Name of the test VM"
  type        = string
  default     = "terraform-vm"
}

variable "machine_type" {
  description = "Machine type for the test VM"
  type        = string
  default     = "e2-micro"
}

variable "environment" {
  description = "Environment label (dev, staging, prod, learning)"
  type        = string
  default     = "learning"
}
EOF

  # terraform.tfvars — variable values
  cat > "$TERRAFORM_DIR/terraform.tfvars" << EOF
project_id  = "${PROJECT_ID}"
region      = "${REGION}"
zone        = "${ZONE}"
bucket_name = "${BUCKET_NAME}"
environment = "learning"
EOF

  # terraform.tfvars.example — template safe to commit
  cat > "$TERRAFORM_DIR/terraform.tfvars.example" << 'EOF'
project_id  = "your-gcp-project-id"
region      = "us-central1"
zone        = "us-central1-a"
bucket_name = "tfstate-your-gcp-project-id"
environment = "learning"
EOF

  # main.tf — VPC, subnet, test VM
  cat > "$TERRAFORM_DIR/main.tf" << 'EOF'
# ----------------------------------------------------------------------------
# VPC Network
# ----------------------------------------------------------------------------
resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
  description             = "VPC network managed by Terraform"
}

# ----------------------------------------------------------------------------
# Subnet
# ----------------------------------------------------------------------------
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.network_name}-subnet"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
  description   = "Primary subnet managed by Terraform"
}

# ----------------------------------------------------------------------------
# Test VM
# ----------------------------------------------------------------------------
resource "google_compute_instance" "test_vm" {
  name         = var.vm_name
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-standard"
    }
  }

  network_interface {
    network    = google_compute_network.vpc.id
    subnetwork = google_compute_subnetwork.subnet.id
  }

  tags = ["terraform-managed"]

  labels = {
    managed-by  = "terraform"
    environment = var.environment
  }
}
EOF

  # outputs.tf — values to display after apply
  cat > "$TERRAFORM_DIR/outputs.tf" << 'EOF'
output "network_name" {
  description = "Name of the created VPC network"
  value       = google_compute_network.vpc.name
}

output "network_self_link" {
  description = "Self-link of the VPC network"
  value       = google_compute_network.vpc.self_link
}

output "subnet_name" {
  description = "Name of the created subnet"
  value       = google_compute_subnetwork.subnet.name
}

output "subnet_cidr" {
  description = "CIDR range of the subnet"
  value       = google_compute_subnetwork.subnet.ip_cidr_range
}

output "vm_name" {
  description = "Name of the test VM"
  value       = google_compute_instance.test_vm.name
}

output "vm_zone" {
  description = "Zone of the test VM"
  value       = google_compute_instance.test_vm.zone
}

output "vm_internal_ip" {
  description = "Internal IP of the test VM"
  value       = google_compute_instance.test_vm.network_interface[0].network_ip
}
EOF

  log_success "Terraform files created"
}

# ----------------------------------------------------------------------------
# Final summary
# ----------------------------------------------------------------------------
print_summary() {
  echo ""
  echo "============================================================================"
  log_success "Bootstrap completed successfully!"
  echo "============================================================================"
  echo ""
  echo "  Project ID      : $PROJECT_ID"
  echo "  Service Account : $SA_EMAIL"
  echo "  State Bucket    : gs://$BUCKET_NAME"
  echo "  JSON Key        : $KEY_FILE"
  echo "  Terraform Dir   : $TERRAFORM_DIR"
  echo ""
  echo "  Assigned roles:"
  for role in "${ROLES[@]}"; do
    echo "    - $role"
  done
  echo ""
  echo "============================================================================"
  echo "  Next steps:"
  echo "============================================================================"
  echo ""
  echo "  1. source .env"
  echo "  2. cd terraform"
  echo "  3. terraform init"
  echo "  4. terraform plan"
  echo "  5. terraform apply"
  echo ""
  log_warn "IMPORTANT: NEVER commit sa-key.json or .env to Git!"
  echo ""
}

# ----------------------------------------------------------------------------
# Main flow
# ----------------------------------------------------------------------------
main() {
  echo "============================================================================"
  echo "  GCP Terraform Bootstrap"
  echo "============================================================================"
  echo ""

  check_prerequisites
  enable_apis
  create_service_account
  assign_iam_roles
  create_state_bucket
  create_sa_key
  create_env_file
  create_gitignore
  create_terraform_files
  print_summary
}

main "$@"