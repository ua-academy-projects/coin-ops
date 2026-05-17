#!/bin/bash
set -e

# === Configuration ===
REGION="eu-central-1"
BUCKET_NAME="devops-intern-penina-tf-state"
DYNAMODB_TABLE="terraform-state-lock"

# === Step 1: Verify AWS credentials ===
echo "Verifying AWS credentials..."
aws sts get-caller-identity
echo "Credentials valid."

# === Step 2: Create S3 bucket for Terraform state ===
echo "Creating state bucket: $BUCKET_NAME..."
if aws s3api head-bucket --bucket $BUCKET_NAME 2>/dev/null; then
  echo "Bucket already exists, skipping."
else
  aws s3api create-bucket \
    --bucket $BUCKET_NAME \
    --region $REGION \
    --create-bucket-configuration LocationConstraint=$REGION
  echo "Bucket created."
fi

# === Step 3: Enable versioning on bucket ===
echo "Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket $BUCKET_NAME \
  --versioning-configuration Status=Enabled
echo "Versioning enabled."

# === Step 4: Block public access ===
echo "Blocking public access..."
aws s3api put-public-access-block \
  --bucket $BUCKET_NAME \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
echo "Public access blocked."

# === Step 5: Create DynamoDB table for state locking ===
echo "Creating DynamoDB table for state locking..."
if aws dynamodb describe-table \
    --table-name $DYNAMODB_TABLE \
    --region $REGION > /dev/null 2>&1; then
  echo "DynamoDB table already exists, skipping."
else
  aws dynamodb create-table \
    --table-name $DYNAMODB_TABLE \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION
  echo "DynamoDB table created."
fi

echo ""
echo "=== Bootstrap complete ==="
echo "Region:        $REGION"
echo "State bucket:  s3://$BUCKET_NAME"
echo "Lock table:    $DYNAMODB_TABLE"
echo ""
echo "Next steps:"
echo "  1. Update backend.tf to use S3 backend"
echo "  2. Run: terraform init -migrate-state"
echo "  3. Run: terraform apply"