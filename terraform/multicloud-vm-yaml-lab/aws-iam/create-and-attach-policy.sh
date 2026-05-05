#!/usr/bin/env bash
set -euo pipefail

: "${IAM_USER:?Set IAM_USER to the IAM user that owns the coinops-lab access key.}"

ADMIN_PROFILE="${ADMIN_PROFILE:-default}"
POLICY_NAME="${POLICY_NAME:-CoinOpsTerraformLabPolicy}"
POLICY_FILE="${POLICY_FILE:-aws-iam/coinops-terraform-lab-policy.json}"

ACCOUNT_ID="$(aws sts get-caller-identity --profile "$ADMIN_PROFILE" --query Account --output text)"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${POLICY_NAME}"

if aws iam get-policy --policy-arn "$POLICY_ARN" --profile "$ADMIN_PROFILE" >/dev/null 2>&1; then
  echo "Policy already exists: $POLICY_ARN"
  VERSION_COUNT="$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --profile "$ADMIN_PROFILE" --query 'length(Versions)' --output text)"
  if [ "$VERSION_COUNT" -ge 5 ]; then
    OLD_VERSION="$(aws iam list-policy-versions --policy-arn "$POLICY_ARN" --profile "$ADMIN_PROFILE" --query 'Versions[?IsDefaultVersion==`false`]|sort_by(@,&CreateDate)[0].VersionId' --output text)"
    aws iam delete-policy-version \
      --policy-arn "$POLICY_ARN" \
      --version-id "$OLD_VERSION" \
      --profile "$ADMIN_PROFILE"
  fi
  aws iam create-policy-version \
    --policy-arn "$POLICY_ARN" \
    --policy-document "file://${POLICY_FILE}" \
    --set-as-default \
    --profile "$ADMIN_PROFILE" \
    --query 'PolicyVersion.VersionId' \
    --output text
else
  aws iam create-policy \
    --policy-name "$POLICY_NAME" \
    --policy-document "file://${POLICY_FILE}" \
    --profile "$ADMIN_PROFILE" \
    --query 'Policy.Arn' \
    --output text
fi

aws iam attach-user-policy \
  --user-name "$IAM_USER" \
  --policy-arn "$POLICY_ARN" \
  --profile "$ADMIN_PROFILE"

echo "Attached $POLICY_ARN to IAM user $IAM_USER"