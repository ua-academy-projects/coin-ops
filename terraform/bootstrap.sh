#!/bin/bash

# Bootstrap script to set up GCP environment for Terraform
# Before running this script, ensure your organization's policy allows Service Account key creation.
# You may need to disable the "iam.disableServiceAccountKeyCreation" policy constraint for your organization.

# Configuration variables
PROJECT_ID="project-6f41102f-c77c-46a3-aac"
SA_NAME="terraform-sa"
BUCKET_NAME="internship-state-bucket"
REGION="europe-central2"

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

# Create GCS Bucket for Terraform remote state
echo "Creating GCS bucket: $BUCKET_NAME"
gcloud storage buckets create "gs://$BUCKET_NAME" --location="$REGION"

# Enable object versioning for state protection
echo "Enabling bucket versioning..."
gcloud storage buckets update "gs://$BUCKET_NAME" --versioning

# Generate Service Account key
echo "Generating JSON key..."
gcloud iam service-accounts keys create sa-key.json \
    --iam-account="$SA_EMAIL"

# Configure local environment and .gitignore
echo "Configuring local environment..."
{
    echo "export GOOGLE_APPLICATION_CREDENTIALS=\"$(pwd)/sa-key.json\""
    echo "export TF_VAR_project_id=\"$PROJECT_ID\""
    echo "export TF_VAR_region=\"$REGION\""
} > .env

echo "Bootstrap completed successfully."