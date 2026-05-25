#!/usr/bin/env bash
# =============================================================================
# AWS Bootstrap Script for Terraform
# =============================================================================
# Creates:
#   - IAM User with least-privilege policies
#   - S3 bucket for Terraform remote state (versioned, encrypted)
#   - DynamoDB table for state locking
#   - Local .env.aws file for Terraform (NOT committed to Git)
#
# Prerequisites:
#   - AWS CLI v2 installed and configured (aws configure)
#   - An IAM user/role with admin access to run this script
#
# Usage:
#   chmod +x bootstrap/aws.sh
#   ./bootstrap/aws.sh
# =============================================================================

set -euo pipefail

# ─── Color output ─────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()    { echo -e "${GREEN}[✓]${NC} $*"; }
info()   { echo -e "${CYAN}[i]${NC} $*"; }
warn()   { echo -e "${YELLOW}[!]${NC} $*"; }
error()  { echo -e "${RED}[✗]${NC} $*"; exit 1; }
header() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"; echo -e "${BOLD}${CYAN}  $*${NC}"; echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}"; }

# ─── Configuration ────────────────────────────────────────────────────────────
REGION="${AWS_REGION:-us-east-1}"
PROJECT_NAME="${PROJECT_NAME:-terraform-project}"
SA_NAME="${SA_NAME:-terraform-sa}"
STATE_BUCKET="${STATE_BUCKET:-${PROJECT_NAME}-tf-state}"
DYNAMO_TABLE="${DYNAMO_TABLE:-${PROJECT_NAME}-tf-lock}"
ENV_FILE="./.env.aws"

# ─── Prerequisite check ───────────────────────────────────────────────────────
header "Checking Prerequisites"

command -v aws >/dev/null 2>&1 || error "AWS CLI not found. Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
command -v terraform >/dev/null 2>&1 || error "terraform not found. Install: https://developer.hashicorp.com/terraform/downloads"

info "AWS CLI version: $(aws --version 2>/dev/null | head -1)"
info "Terraform version: $(terraform version -json 2>/dev/null | python3 -c 'import sys,json; print(json.load(sys.stdin)["terraform_version"])' 2>/dev/null || terraform version | head -1)"

# Check AWS auth
AWS_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null || echo "")
if [[ -z "$AWS_IDENTITY" ]]; then
  error "Not authenticated with AWS. Run 'aws configure' first."
else
  log "Authenticated as: ${AWS_IDENTITY}"
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
info "Account ID: ${AWS_ACCOUNT_ID}"

# ─── S3 Bucket for Terraform State ──────────────────────────────────────────
header "Creating S3 State Bucket"

if aws s3api head-bucket --bucket "$STATE_BUCKET" 2>/dev/null; then
  warn "Bucket '${STATE_BUCKET}' already exists. Reusing it."
else
  info "Creating bucket: ${STATE_BUCKET}"

  if [[ "$REGION" == "us-east-1" ]]; then
    # us-east-1 doesn't accept LocationConstraint
    aws s3api create-bucket \
      --bucket "$STATE_BUCKET" \
      --region "$REGION"
  else
    aws s3api create-bucket \
      --bucket "$STATE_BUCKET" \
      --region "$REGION" \
      --create-bucket-configuration LocationConstraint="$REGION"
  fi
  log "Bucket created: ${STATE_BUCKET}"
fi

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled
log "Versioning enabled on state bucket"

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": true
    }]
  }'
log "Server-side encryption enabled (AES256)"

# Block public access
aws s3api put-public-access-block \
  --bucket "$STATE_BUCKET" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
log "Public access blocked on state bucket"

# ─── DynamoDB Table for State Locking ────────────────────────────────────────
header "Creating DynamoDB Lock Table"

if aws dynamodb describe-table --table-name "$DYNAMO_TABLE" --region "$REGION" &>/dev/null; then
  warn "DynamoDB table '${DYNAMO_TABLE}' already exists. Reusing it."
else
  aws dynamodb create-table \
    --table-name "$DYNAMO_TABLE" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "$REGION"
  log "DynamoDB table created: ${DYNAMO_TABLE}"

  info "Waiting for table to become active..."
  aws dynamodb wait table-exists --table-name "$DYNAMO_TABLE" --region "$REGION"
  log "Table is active"
fi

# ─── IAM User for Terraform ─────────────────────────────────────────────────
header "Creating IAM User for Terraform"

if aws iam get-user --user-name "$SA_NAME" &>/dev/null; then
  warn "IAM user '${SA_NAME}' already exists. Reusing it."
else
  aws iam create-user --user-name "$SA_NAME"
  log "IAM user created: ${SA_NAME}"
fi

# ─── IAM Policy (Least Privilege) ───────────────────────────────────────────
POLICY_NAME="${SA_NAME}-policy"
POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"

POLICY_DOC=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformStateAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${STATE_BUCKET}",
        "arn:aws:s3:::${STATE_BUCKET}/*"
      ]
    },
    {
      "Sid": "TerraformStateLocking",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
        "dynamodb:DescribeTable"
      ],
      "Resource": "arn:aws:dynamodb:${REGION}:${AWS_ACCOUNT_ID}:table/${DYNAMO_TABLE}"
    },
    {
      "Sid": "EC2Management",
      "Effect": "Allow",
      "Action": [
        "ec2:*"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "${REGION}"
        }
      }
    },
    {
      "Sid": "EC2ReadOnly",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "ec2:Get*"
      ],
      "Resource": "*"
    }
  ]
}
EOF
)

# Create or update the policy
if aws iam get-policy --policy-arn "$POLICY_ARN" &>/dev/null; then
  warn "Policy '${POLICY_NAME}' already exists. Creating new version."
  aws iam create-policy-version \
    --policy-arn "$POLICY_ARN" \
    --policy-document "$POLICY_DOC" \
    --set-as-default
else
  aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document "$POLICY_DOC"
  log "IAM policy created: ${POLICY_NAME}"
fi

# Attach policy to user
aws iam attach-user-policy \
  --user-name "$SA_NAME" \
  --policy-arn "$POLICY_ARN"
log "Policy attached to user"

# ─── Access Keys ─────────────────────────────────────────────────────────────
header "Generating Access Keys"

# Check if keys already exist
EXISTING_KEYS=$(aws iam list-access-keys --user-name "$SA_NAME" --query 'AccessKeyMetadata[].AccessKeyId' --output text)
if [[ -n "$EXISTING_KEYS" ]]; then
  warn "Access keys already exist for '${SA_NAME}'. Skipping key creation."
  warn "If you need new keys, delete the existing ones first:"
  warn "  aws iam delete-access-key --user-name ${SA_NAME} --access-key-id <KEY_ID>"

  # Write env file with placeholder
  cat > "$ENV_FILE" <<EOF
# ============================================================
# AWS Terraform environment config — generated by bootstrap/aws.sh
# DO NOT commit this file to Git!
# Source before running Terraform: source .env.aws
# ============================================================

export AWS_REGION="${REGION}"
export TF_VAR_aws_region="${REGION}"
export TF_VAR_state_bucket="${STATE_BUCKET}"
export TF_VAR_cloud_provider="aws"

# ⚠ Access keys already existed — fill in manually:
export AWS_ACCESS_KEY_ID="FILL_IN_YOUR_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="FILL_IN_YOUR_SECRET_KEY"
EOF
else
  # Create new access key
  KEY_OUTPUT=$(aws iam create-access-key --user-name "$SA_NAME" --output json)
  ACCESS_KEY=$(echo "$KEY_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKey']['AccessKeyId'])")
  SECRET_KEY=$(echo "$KEY_OUTPUT" | python3 -c "import sys,json; print(json.load(sys.stdin)['AccessKey']['SecretAccessKey'])")

  log "Access key created: ${ACCESS_KEY}"
  warn "⚠ The secret key is shown only once. It's saved in ${ENV_FILE}"

  # ─── Write .env.aws ──────────────────────────────────────────────────────
  cat > "$ENV_FILE" <<EOF
# ============================================================
# AWS Terraform environment config — generated by bootstrap/aws.sh
# DO NOT commit this file to Git!
# Source before running Terraform: source .env.aws
# ============================================================

export AWS_REGION="${REGION}"
export AWS_ACCESS_KEY_ID="${ACCESS_KEY}"
export AWS_SECRET_ACCESS_KEY="${SECRET_KEY}"

export TF_VAR_aws_region="${REGION}"
export TF_VAR_state_bucket="${STATE_BUCKET}"
export TF_VAR_cloud_provider="aws"
EOF
fi

chmod 600 "$ENV_FILE"
log "Environment file written: ${ENV_FILE}"
warn "⚠ Source it before running Terraform: source ${ENV_FILE}"

# ─── Summary ─────────────────────────────────────────────────────────────────
header "Bootstrap Complete"

echo ""
echo -e "  ${BOLD}AWS Account:${NC}     ${AWS_ACCOUNT_ID}"
echo -e "  ${BOLD}Region:${NC}          ${REGION}"
echo -e "  ${BOLD}IAM User:${NC}        ${SA_NAME}"
echo -e "  ${BOLD}State Bucket:${NC}    s3://${STATE_BUCKET}"
echo -e "  ${BOLD}Lock Table:${NC}      ${DYNAMO_TABLE}"
echo -e "  ${BOLD}Env File:${NC}        ${ENV_FILE}"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo -e "  1. source ${ENV_FILE}"
echo -e "  2. Uncomment S3 backend in versions.tf (comment out GCS)"
echo -e "  3. terraform init \\"
echo -e "       -backend-config=\"bucket=${STATE_BUCKET}\" \\"
echo -e "       -backend-config=\"key=terraform/state/terraform.tfstate\" \\"
echo -e "       -backend-config=\"region=${REGION}\" \\"
echo -e "       -backend-config=\"dynamodb_table=${DYNAMO_TABLE}\""
echo -e "  4. terraform plan -var-file=aws.tfvars"
echo -e "  5. terraform apply -var-file=aws.tfvars"
echo ""
