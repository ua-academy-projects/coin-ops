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

# === Step 6: Create terraform-sa IAM user if not exists ===
echo "Setting up terraform-sa IAM user..."
if aws iam get-user --user-name terraform-sa > /dev/null 2>&1; then
  echo "User terraform-sa already exists, skipping creation."
else
  aws iam create-user --user-name terraform-sa
  echo "User created."
fi

# === Step 7: Create least-privilege policy for terraform-sa ===
echo "Creating Terraform least-privilege policy..."
POLICY_NAME="TerraformCoinOpsPolicy"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

POLICY_DOC=$(cat <<'POLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EC2AndVPC",
      "Effect": "Allow",
      "Action": [
        "ec2:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "LoadBalancing",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:*"
      ],
      "Resource": "*"
    },
    {
      "Sid": "S3",
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": "*"
    },
    {
      "Sid": "DynamoDB",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
        "dynamodb:DescribeTable",
        "dynamodb:CreateTable",
        "dynamodb:DeleteTable"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatch",
      "Effect": "Allow",
      "Action": [
        "cloudwatch:PutMetricAlarm",
        "cloudwatch:DeleteAlarms",
        "cloudwatch:DescribeAlarms",
        "cloudwatch:PutDashboard",
        "cloudwatch:DeleteDashboards",
        "cloudwatch:GetDashboard",
        "cloudwatch:ListDashboards",
        "cloudwatch:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:DeleteLogGroup",
        "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy",
        "logs:PutMetricFilter",
        "logs:DeleteMetricFilter",
        "logs:DescribeMetricFilters",
        "logs:TagLogGroup",
        "logs:ListTagsLogGroup",
        "logs:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SNS",
      "Effect": "Allow",
      "Action": [
        "sns:CreateTopic",
        "sns:DeleteTopic",
        "sns:GetTopicAttributes",
        "sns:SetTopicAttributes",
        "sns:Subscribe",
        "sns:Unsubscribe",
        "sns:ListSubscriptionsByTopic",
        "sns:TagResource",
        "sns:UntagResource",
        "sns:GetSubscriptionAttributes",
        "sns:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SSM",
      "Effect": "Allow",
      "Action": [
        "ssm:PutParameter",
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:DeleteParameter",
        "ssm:DescribeParameters",
        "ssm:AddTagsToResource",
        "ssm:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "IAMForCloudWatchAgent",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:PassRole",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:CreateInstanceProfile",
        "iam:DeleteInstanceProfile",
        "iam:GetInstanceProfile",
        "iam:AddRoleToInstanceProfile",
        "iam:RemoveRoleFromInstanceProfile",
        "iam:ListInstanceProfilesForRole",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:ListRolePolicies",
        "iam:GetRolePolicy",
        "iam:ListRoleTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "KeyPair",
      "Effect": "Allow",
      "Action": [
        "ec2:ImportKeyPair",
        "ec2:DeleteKeyPair",
        "ec2:DescribeKeyPairs"
      ],
      "Resource": "*"
    }
  ]
}
POLICY
)

# Create or update policy
if aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}" > /dev/null 2>&1; then
  echo "Policy already exists, updating..."
  VERSION_ID=$(aws iam list-policy-versions \
    --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}" \
    --query 'Versions[?!IsDefaultVersion].VersionId' \
    --output text | awk '{print $1}')
  if [ -n "$VERSION_ID" ]; then
    aws iam delete-policy-version \
      --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}" \
      --version-id "$VERSION_ID"
  fi
  aws iam create-policy-version \
    --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}" \
    --policy-document "$POLICY_DOC" \
    --set-as-default
else
  echo "Creating new policy..."
  aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document "$POLICY_DOC"
fi
echo "Policy ready."

# === Step 8: Attach policy to terraform-sa ===
echo "Attaching policy to terraform-sa..."
aws iam attach-user-policy \
  --user-name terraform-sa \
  --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}" \
  && echo "Policy attached." || echo "Already attached."

# === Step 9: Create access keys for terraform-sa ===
echo "Creating access keys for terraform-sa..."
EXISTING_KEYS=$(aws iam list-access-keys --user-name terraform-sa \
  --query 'AccessKeyMetadata[].AccessKeyId' --output text)

if [ -n "$EXISTING_KEYS" ]; then
  echo "Access keys already exist — skipping creation."
  echo "To rotate keys: delete existing keys in AWS Console and re-run bootstrap."
else
  KEYS=$(aws iam create-access-key --user-name terraform-sa)
  ACCESS_KEY=$(echo $KEYS | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['AccessKey']['AccessKeyId'])")
  SECRET_KEY=$(echo $KEYS | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['AccessKey']['SecretAccessKey'])")
  echo ""
  echo "=== NEW CREDENTIALS — save to terraform.tfvars ==="
  echo "aws_access_key = \"${ACCESS_KEY}\""
  echo "aws_secret_key = \"${SECRET_KEY}\""
  echo "==================================================="
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