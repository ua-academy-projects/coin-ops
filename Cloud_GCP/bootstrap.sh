#!/bin/bash
set -e

# === Configuration ===
PROJECT_ID="devops-intern-penina"
PROJECT_NAME="DevOps Internship"
BILLING_ACCOUNT="01B2AF-4F7EA9-68F4C6"
REGION="europe-central2"
SA_NAME="terraform-sa"
SA_DISPLAY_NAME="Terraform Service Account"
BUCKET_NAME="${PROJECT_ID}-tf-state"

# === Step 1: Create project ===
echo "Creating project: $PROJECT_ID..."
if gcloud projects describe $PROJECT_ID > /dev/null 2>&1; then
  echo "Project already exists, skipping."
else
  gcloud projects create $PROJECT_ID --name="$PROJECT_NAME"
fi

# === Step 2: Link billing ===
echo "Linking billing account..."
gcloud billing projects link $PROJECT_ID --billing-account=$BILLING_ACCOUNT

# === Step 3: Set project as default ===
echo "Setting default project..."
gcloud config set project $PROJECT_ID

# === Step 4: Enable APIs ===
echo "Enabling APIs..."
gcloud services enable compute.googleapis.com
gcloud services enable storage.googleapis.com
gcloud services enable iam.googleapis.com
gcloud services enable cloudresourcemanager.googleapis.com

# === Step 5: Create service account ===
echo "Creating service account: $SA_NAME..."
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
if gcloud iam service-accounts describe $SA_EMAIL > /dev/null 2>&1; then
  echo "Service account already exists, skipping."
else
  gcloud iam service-accounts create $SA_NAME \
    --display-name="$SA_DISPLAY_NAME" \
    --project=$PROJECT_ID
fi

# === Step 6: Assign IAM roles ===
echo "Assigning roles to $SA_EMAIL..."

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/compute.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:$SA_EMAIL" \
  --role="roles/iam.serviceAccountUser"

# === Step 7: Create service account key ===
echo "Creating key file..."
if [ -f key.json ]; then
  echo "Key file already exists, skipping."
else
  gcloud iam service-accounts keys create key.json \
    --iam-account=$SA_EMAIL
fi

# === Step 8: Create GCS bucket for Terraform state ===
echo "Creating state bucket: $BUCKET_NAME..."
if gcloud storage buckets describe gs://$BUCKET_NAME > /dev/null 2>&1; then
  echo "Bucket already exists, skipping."
else
  gcloud storage buckets create gs://$BUCKET_NAME \
    --location=$REGION \
    --project=$PROJECT_ID
fi

echo ""
echo "=== Bootstrap complete ==="
echo "Project:         $PROJECT_ID"
echo "Service Account: $SA_EMAIL"
echo "Key file:        key.json"
echo "State bucket:    gs://$BUCKET_NAME"
echo ""
echo "To use with Terraform, set:"
echo "  export GOOGLE_APPLICATION_CREDENTIALS=key.json"