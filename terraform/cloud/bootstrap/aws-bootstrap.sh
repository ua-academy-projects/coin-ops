#!/usr/bin/env bash
# AWS Bootstrap Script
# Purpose: Prepare an AWS account for infrastructure provisioning
# Steps:
#   1) Validate required tools and active AWS CLI credentials
#   2) Create backend S3 storage for Terraform state
#   3) Enable S3 bucket versioning and encryption
#   4) Create a DynamoDB table for Terraform state locking
#   5) Create a Terraform IAM user
#   6) Assign required IAM permissions
#   7) Create an access key for the Terraform IAM user
#   8) Create required secret entries with placeholder values
#   9) Create an environment file
#
# Usage:
#   1. Export AWS_REGION before running
#   2. chmod +x aws-bootstrap.sh
#   3. aws configure
#   4. ./aws-bootstrap.sh
#   5. Replace placeholder secret values in AWS Secrets Manager

set -euo pipefail
# -e -> exit on error
# -u -> exit on unset variable
# -o pipefail -> exit on pipe failure

# ------------------------------------------------------------
# Variables
# ------------------------------------------------------------
AWS_REGION="${AWS_REGION}"

IAM_USER_NAME="${IAM_USER_NAME:-coin-ops-terraform}"
POLICY_NAME="${POLICY_NAME:-coin-ops-terraform-policy}"
BUCKET_NAME="${BUCKET_NAME:-coin-ops-tfstate-$(aws sts get-caller-identity --query Account --output text)}"
LOCK_TABLE_NAME="${LOCK_TABLE_NAME:-coin-ops-tfstate-locks}"
ENV_FILE="${ENV_FILE:-./terraform.env}"
SECRET_PLACEHOLDER_VALUE="${SECRET_PLACEHOLDER_VALUE:-CHANGE_ME_IN_SECRETS_MANAGER}"

REQUIRED_SECRETS=(
  "ghcr-username"
  "ghcr-token"
  "rabbitmq-password"
  "db-password"
)

# ------------------------------------------------------------
# Validate required variables
# ------------------------------------------------------------
for var in \
  AWS_REGION \
  IAM_USER_NAME \
  POLICY_NAME \
  BUCKET_NAME \
  LOCK_TABLE_NAME \
  ENV_FILE \
  SECRET_PLACEHOLDER_VALUE; do
  if [[ -z "${!var}" ]]; then
    echo "ERROR: $var is not set."
    exit 1
  fi
done

if [[ ${#REQUIRED_SECRETS[@]} -eq 0 ]]; then
  echo "ERROR: REQUIRED_SECRETS is empty. Add at least one secret name."
  exit 1
fi

# ------------------------------------------------------------
# 1) Check required tools and active credentials
# ------------------------------------------------------------
echo ""
echo "==> Step 1: Tooling and Login"
if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is not installed"
  exit 1
fi

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
AWS_CALLER_ARN="$(aws sts get-caller-identity --query Arn --output text)"
echo "Using account: ${AWS_ACCOUNT_ID}"
echo "Logged in as: ${AWS_CALLER_ARN}"

# ------------------------------------------------------------
# 2) Create state bucket
# ------------------------------------------------------------
echo ""
echo "==> Step 2: State Bucket"
if aws s3api head-bucket --bucket "${BUCKET_NAME}" >/dev/null 2>&1; then
  echo "Bucket s3://${BUCKET_NAME} already exists, skipping"
else
  echo "Creating bucket s3://${BUCKET_NAME}..."
  if [[ "${AWS_REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${AWS_REGION}" >/dev/null
  else
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${AWS_REGION}" \
      --create-bucket-configuration "LocationConstraint=${AWS_REGION}" >/dev/null
  fi
fi

# ------------------------------------------------------------
# 3) Enable bucket safety settings
# ------------------------------------------------------------
echo ""
echo "==> Step 3: Bucket Versioning and Encryption"
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled >/dev/null

aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{
    "Rules": [
      {
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }
    ]
  }' >/dev/null

# ------------------------------------------------------------
# 4) Create lock table
# ------------------------------------------------------------
echo ""
echo "==> Step 4: DynamoDB Lock Table"
if aws dynamodb describe-table \
  --table-name "${LOCK_TABLE_NAME}" \
  --region "${AWS_REGION}" >/dev/null 2>&1; then
  echo "DynamoDB table ${LOCK_TABLE_NAME} already exists, skipping"
else
  aws dynamodb create-table \
    --table-name "${LOCK_TABLE_NAME}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${AWS_REGION}" >/dev/null

  aws dynamodb wait table-exists \
    --table-name "${LOCK_TABLE_NAME}" \
    --region "${AWS_REGION}"

  echo "DynamoDB table created: ${LOCK_TABLE_NAME}"
fi

# ------------------------------------------------------------
# 5) Create IAM user
# ------------------------------------------------------------
echo ""
echo "==> Step 5: IAM User"
if aws iam get-user --user-name "${IAM_USER_NAME}" >/dev/null 2>&1; then
  echo "IAM user ${IAM_USER_NAME} already exists, skipping"
else
  aws iam create-user --user-name "${IAM_USER_NAME}" >/dev/null
  echo "IAM user created: ${IAM_USER_NAME}"
fi

# ------------------------------------------------------------
# 6) Assign IAM permissions
# ------------------------------------------------------------
echo ""
echo "==> Step 6: IAM Policy"
POLICY_DOCUMENT="$(mktemp)"
cat > "${POLICY_DOCUMENT}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "rds:*",
        "secretsmanager:*",
        "iam:*",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketVersioning",
        "s3:PutBucketVersioning",
        "s3:GetBucketEncryption",
        "s3:PutBucketEncryption"
      ],
      "Resource": "arn:aws:s3:::${BUCKET_NAME}"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem"
      ],
      "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${LOCK_TABLE_NAME}"
    }
  ]
}
EOF

aws iam put-user-policy \
  --user-name "${IAM_USER_NAME}" \
  --policy-name "${POLICY_NAME}" \
  --policy-document "file://${POLICY_DOCUMENT}" >/dev/null

rm -f "${POLICY_DOCUMENT}"
echo "IAM policy attached: ${POLICY_NAME}"

# ------------------------------------------------------------
# 7) Create access key
# ------------------------------------------------------------
echo ""
echo "==> Step 7: Access Key"
ACCESS_KEY_COUNT="$(aws iam list-access-keys \
  --user-name "${IAM_USER_NAME}" \
  --query 'length(AccessKeyMetadata)' \
  --output text)"

AWS_ACCESS_KEY_ID_VALUE=""
AWS_SECRET_ACCESS_KEY_VALUE=""

if [[ "${ACCESS_KEY_COUNT}" -ge 1 ]]; then
  echo "IAM user already has an access key. Existing secret keys cannot be retrieved."
  echo "Run 'aws iam create-access-key --user-name ${IAM_USER_NAME}' manually if you need a new key."
else
  ACCESS_KEY_JSON="$(aws iam create-access-key --user-name "${IAM_USER_NAME}")"
  AWS_ACCESS_KEY_ID_VALUE="$(printf "%s" "${ACCESS_KEY_JSON}" | awk -F\" '/AccessKeyId/ {print $4}')"
  AWS_SECRET_ACCESS_KEY_VALUE="$(printf "%s" "${ACCESS_KEY_JSON}" | awk -F\" '/SecretAccessKey/ {print $4}')"
  echo "Access key created for ${IAM_USER_NAME}"
fi

# ------------------------------------------------------------
# 8) Create required secrets
# ------------------------------------------------------------
echo ""
echo "==> Step 8: Secrets Manager"
for SECRET_NAME in "${REQUIRED_SECRETS[@]}"; do
  if aws secretsmanager describe-secret \
    --secret-id "${SECRET_NAME}" \
    --region "${AWS_REGION}" >/dev/null 2>&1; then
    echo "Secret already exists: ${SECRET_NAME}"
  else
    aws secretsmanager create-secret \
      --name "${SECRET_NAME}" \
      --secret-string "${SECRET_PLACEHOLDER_VALUE}" \
      --region "${AWS_REGION}" >/dev/null

    echo "Secret created with placeholder value: ${SECRET_NAME}"
  fi
done

echo ""
echo "WARNING: Required secrets now exist in Secrets Manager, but may still contain the bootstrap placeholder."
echo "WARNING: Replace placeholder values for:"
for SECRET_NAME in "${REQUIRED_SECRETS[@]}"; do
  echo " - ${SECRET_NAME}"
done

# ------------------------------------------------------------
# 9) Create environment file
# ------------------------------------------------------------
echo ""
echo "==> Step 9: Environment File"
cat > "${ENV_FILE}" <<EOF
export AWS_REGION="${AWS_REGION}"
export AWS_DEFAULT_REGION="${AWS_REGION}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID_VALUE}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY_VALUE}"

export TF_STATE_BUCKET="${BUCKET_NAME}"
export TF_STATE_LOCK_TABLE="${LOCK_TABLE_NAME}"
EOF

chmod 600 "${ENV_FILE}"

printf "\nDone!\n"
printf "  %-20s %s\n" "Account:"       "${AWS_ACCOUNT_ID}"
printf "  %-20s %s\n" "Region:"        "${AWS_REGION}"
printf "  %-20s %s\n" "IAM user:"      "${IAM_USER_NAME}"
printf "  %-20s %s\n" "State storage:" "s3://${BUCKET_NAME}"
printf "  %-20s %s\n" "Lock table:"    "${LOCK_TABLE_NAME}"
printf "  %-20s %s\n" "Env file:"      "${ENV_FILE}"
printf "\nNext steps:\n"
printf "  update placeholder secrets in Secrets Manager\n"
printf "  source %s\n" "${ENV_FILE}"
printf "  terraform init\n"
printf "\nIMPORTANT: Add %s to your .gitignore because it may contain secrets.\n" "${ENV_FILE}"
