#!/bin/bash
set -e

# === Configuration ===
REGION="eu-central-1"
BUCKET_NAME="devops-intern-penina-tf-state"
PROFILE="default"

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
if aws dynamodb describe-table --table-name terraform-state-lock --region $REGION 2>/dev/null; then
  echo "DynamoDB table already exists, skipping."
else
  aws dynamodb create-table \
    --table-name terraform-state-lock \
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
echo "Lock table:    terraform-state-lock"
echo ""
echo "Update backend.tf with:"
echo "  bucket         = \"$BUCKET_NAME\""
echo "  key            = \"coinops/terraform.tfstate\""
echo "  region         = \"$REGION\""
echo "  dynamodb_table = \"terraform-state-lock\""