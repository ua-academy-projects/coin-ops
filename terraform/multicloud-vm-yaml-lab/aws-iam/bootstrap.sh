#!/usr/bin/env bash
set -euo pipefail

: "${IAM_USER:?Set IAM_USER to the IAM user that owns the lab access key.}"

ADMIN_PROFILE="${ADMIN_PROFILE:-default}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
NAME_PREFIX="${NAME_PREFIX:-coinops-lab}"
STATE_BUCKET="${STATE_BUCKET:-coinops-leev1tan-terraform-state-001}"
APP_ROLE_NAME="${APP_ROLE_NAME:-${NAME_PREFIX}-app-runtime-role}"
APP_INSTANCE_PROFILE_NAME="${APP_INSTANCE_PROFILE_NAME:-${NAME_PREFIX}-app-runtime-profile}"
OLD_QUEUE_ROLE_NAME="${OLD_QUEUE_ROLE_NAME:-${NAME_PREFIX}-app-queue-role}"
OLD_QUEUE_PROFILE_NAME="${OLD_QUEUE_PROFILE_NAME:-${NAME_PREFIX}-app-queue-profile}"
OLD_QUEUE_POLICY_NAME="${OLD_QUEUE_POLICY_NAME:-${NAME_PREFIX}-app-queue-policy}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

aws_admin() {
  aws --profile "$ADMIN_PROFILE" "$@"
}

ACCOUNT_ID="$(aws_admin sts get-caller-identity --query Account --output text)"

ensure_policy() {
  local policy_name="$1"
  local policy_file="$2"
  local policy_arn="arn:aws:iam::${ACCOUNT_ID}:policy/${policy_name}"

  if aws_admin iam get-policy --policy-arn "$policy_arn" >/dev/null 2>&1; then
    local version_count
    version_count="$(aws_admin iam list-policy-versions --policy-arn "$policy_arn" --query 'length(Versions)' --output text)"
    if [ "$version_count" -ge 5 ]; then
      local old_version
      old_version="$(aws_admin iam list-policy-versions --policy-arn "$policy_arn" --query 'Versions[?IsDefaultVersion==`false`]|sort_by(@,&CreateDate)[0].VersionId' --output text)"
      aws_admin iam delete-policy-version --policy-arn "$policy_arn" --version-id "$old_version"
    fi
    aws_admin iam create-policy-version \
      --policy-arn "$policy_arn" \
      --policy-document "file://${policy_file}" \
      --set-as-default \
      --query 'PolicyVersion.VersionId' \
      --output text >/dev/null
  else
    aws_admin iam create-policy \
      --policy-name "$policy_name" \
      --policy-document "file://${policy_file}" \
      --query 'Policy.Arn' \
      --output text >/dev/null
  fi

  aws_admin iam attach-user-policy \
    --user-name "$IAM_USER" \
    --policy-arn "$policy_arn"

  echo "Attached $policy_arn to IAM user $IAM_USER"
}


cleanup_old_queue_iam() {
  local old_policy_arn="arn:aws:iam::${ACCOUNT_ID}:policy/${OLD_QUEUE_POLICY_NAME}"

  if aws_admin iam get-instance-profile --instance-profile-name "$OLD_QUEUE_PROFILE_NAME" >/dev/null 2>&1; then
    if aws_admin iam get-role --role-name "$OLD_QUEUE_ROLE_NAME" >/dev/null 2>&1; then
      aws_admin iam remove-role-from-instance-profile         --instance-profile-name "$OLD_QUEUE_PROFILE_NAME"         --role-name "$OLD_QUEUE_ROLE_NAME" >/dev/null 2>&1 || true
    fi
    aws_admin iam delete-instance-profile --instance-profile-name "$OLD_QUEUE_PROFILE_NAME" >/dev/null 2>&1 || true
    echo "Removed old queue instance profile if present: $OLD_QUEUE_PROFILE_NAME"
  fi

  if aws_admin iam get-policy --policy-arn "$old_policy_arn" >/dev/null 2>&1; then
    if aws_admin iam get-role --role-name "$OLD_QUEUE_ROLE_NAME" >/dev/null 2>&1; then
      aws_admin iam detach-role-policy --role-name "$OLD_QUEUE_ROLE_NAME" --policy-arn "$old_policy_arn" >/dev/null 2>&1 || true
    fi
    aws_admin iam delete-policy --policy-arn "$old_policy_arn" >/dev/null 2>&1 || true
    echo "Removed old queue policy if present: $old_policy_arn"
  fi

  if aws_admin iam get-role --role-name "$OLD_QUEUE_ROLE_NAME" >/dev/null 2>&1; then
    aws_admin iam delete-role --role-name "$OLD_QUEUE_ROLE_NAME" >/dev/null 2>&1 || true
    echo "Removed old queue role if present: $OLD_QUEUE_ROLE_NAME"
  fi
}

ensure_service_linked_role() {
  local service_name="$1"
  local role_name="$2"

  if aws_admin iam get-role --role-name "$role_name" >/dev/null 2>&1; then
    echo "Service-linked role exists: $role_name"
    return
  fi

  aws_admin iam create-service-linked-role --aws-service-name "$service_name" >/dev/null
  echo "Created service-linked role: $role_name"
}

cat > "$TMP_DIR/state-policy.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "TerraformStateBucketAccess",
      "Effect": "Allow",
      "Action": ["s3:GetBucketLocation", "s3:ListBucket"],
      "Resource": "arn:aws:s3:::${STATE_BUCKET}"
    },
    {
      "Sid": "TerraformStateObjectAccess",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": [
        "arn:aws:s3:::${STATE_BUCKET}/multicloud-vm-yaml-lab/*",
        "arn:aws:s3:::${STATE_BUCKET}/aws/multicloud-vm-yaml-lab/*",
        "arn:aws:s3:::${STATE_BUCKET}/env:/*/multicloud-vm-yaml-lab/*"
      ]
    }
  ]
}
JSON

cat > "$TMP_DIR/network-compute-lb-policy.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "Ec2ReadForPlanning",
      "Effect": "Allow",
      "Action": ["ec2:Describe*", "ec2:GetInstanceTypesFromInstanceRequirements", "ec2:GetSecurityGroupsForVpc"],
      "Resource": "*",
      "Condition": {"StringEquals": {"aws:RequestedRegion": "${AWS_REGION}"}}
    },
    {
      "Sid": "Ec2ManageLabResources",
      "Effect": "Allow",
      "Action": [
        "ec2:AllocateAddress", "ec2:AttachInternetGateway", "ec2:AssociateAddress",
        "ec2:AssociateRouteTable", "ec2:AuthorizeSecurityGroupEgress", "ec2:AuthorizeSecurityGroupIngress",
        "ec2:CreateInternetGateway", "ec2:CreateKeyPair", "ec2:CreateNatGateway",
        "ec2:CreateRoute", "ec2:CreateRouteTable", "ec2:CreateSecurityGroup", "ec2:CreateSubnet",
        "ec2:CreateTags", "ec2:CreateVpc", "ec2:DeleteInternetGateway", "ec2:DeleteKeyPair",
        "ec2:DeleteNatGateway", "ec2:DeleteRoute", "ec2:DeleteRouteTable", "ec2:DeleteSecurityGroup",
        "ec2:DeleteSubnet", "ec2:DeleteTags", "ec2:DeleteVpc", "ec2:DetachInternetGateway",
        "ec2:DisassociateAddress", "ec2:DisassociateRouteTable", "ec2:ImportKeyPair",
        "ec2:ModifySubnetAttribute", "ec2:ModifyVpcAttribute", "ec2:ReleaseAddress",
        "ec2:RevokeSecurityGroupEgress", "ec2:RevokeSecurityGroupIngress", "ec2:RunInstances",
        "ec2:TerminateInstances"
      ],
      "Resource": "*",
      "Condition": {"StringEquals": {"aws:RequestedRegion": "${AWS_REGION}"}}
    },
    {
      "Sid": "ElasticLoadBalancingManageLabResources",
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:AddTags", "elasticloadbalancing:CreateListener",
        "elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateTargetGroup",
        "elasticloadbalancing:DeleteListener", "elasticloadbalancing:DeleteLoadBalancer",
        "elasticloadbalancing:DeleteTargetGroup", "elasticloadbalancing:DeregisterTargets",
        "elasticloadbalancing:Describe*", "elasticloadbalancing:ModifyListener",
        "elasticloadbalancing:ModifyLoadBalancerAttributes", "elasticloadbalancing:ModifyTargetGroup",
        "elasticloadbalancing:ModifyTargetGroupAttributes", "elasticloadbalancing:RegisterTargets",
        "elasticloadbalancing:RemoveTags", "elasticloadbalancing:SetSecurityGroups",
        "elasticloadbalancing:SetSubnets"
      ],
      "Resource": "*"
    },
    {
      "Sid": "AcmManageLabCertificate",
      "Effect": "Allow",
      "Action": [
        "acm:AddTagsToCertificate", "acm:DeleteCertificate", "acm:DescribeCertificate",
        "acm:ListCertificates", "acm:ListTagsForCertificate", "acm:RemoveTagsFromCertificate",
        "acm:RequestCertificate"
      ],
      "Resource": "*"
    }
  ]
}
JSON

cat > "$TMP_DIR/data-runtime-policy.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SecretsManagerReadList",
      "Effect": "Allow",
      "Action": ["secretsmanager:ListSecrets"],
      "Resource": "*"
    },
    {
      "Sid": "SecretsManagerManageLabSecrets",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:CreateSecret", "secretsmanager:DeleteSecret", "secretsmanager:DescribeSecret",
        "secretsmanager:GetSecretValue", "secretsmanager:GetResourcePolicy", "secretsmanager:ListSecretVersionIds",
        "secretsmanager:ListTagsForResource", "secretsmanager:PutSecretValue",
        "secretsmanager:RestoreSecret", "secretsmanager:TagResource", "secretsmanager:UntagResource",
        "secretsmanager:UpdateSecret"
      ],
      "Resource": "arn:aws:secretsmanager:${AWS_REGION}:${ACCOUNT_ID}:secret:${NAME_PREFIX}/*"
    },
    {
      "Sid": "SqsManageLabQueues",
      "Effect": "Allow",
      "Action": [
        "sqs:CreateQueue", "sqs:DeleteQueue", "sqs:GetQueueAttributes", "sqs:GetQueueUrl",
        "sqs:ListQueueTags", "sqs:ListQueues", "sqs:PurgeQueue", "sqs:SetQueueAttributes",
        "sqs:TagQueue", "sqs:UntagQueue"
      ],
      "Resource": "arn:aws:sqs:${AWS_REGION}:${ACCOUNT_ID}:${NAME_PREFIX}-*"
    },
    {
      "Sid": "RdsManageLabDatabase",
      "Effect": "Allow",
      "Action": [
        "rds:AddTagsToResource", "rds:CreateDBInstance", "rds:CreateDBSubnetGroup",
        "rds:DeleteDBInstance", "rds:DeleteDBSubnetGroup", "rds:Describe*",
        "rds:ListTagsForResource", "rds:ModifyDBInstance", "rds:ModifyDBSubnetGroup",
        "rds:RemoveTagsFromResource"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ElastiCacheManageLabCache",
      "Effect": "Allow",
      "Action": [
        "elasticache:AddTagsToResource", "elasticache:CreateCacheSubnetGroup",
        "elasticache:CreateReplicationGroup", "elasticache:DeleteCacheSubnetGroup",
        "elasticache:DeleteReplicationGroup", "elasticache:Describe*",
        "elasticache:ListTagsForResource", "elasticache:ModifyCacheSubnetGroup",
        "elasticache:ModifyReplicationGroup", "elasticache:RemoveTagsFromResource"
      ],
      "Resource": "*"
    }
  ]
}
JSON

cat > "$TMP_DIR/pass-role-policy.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadCoinOpsRuntimeRole",
      "Effect": "Allow",
      "Action": [
        "iam:GetRole", "iam:GetInstanceProfile", "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfileTags", "iam:ListPolicyTags", "iam:ListRolePolicies", "iam:ListRoleTags"
      ],
      "Resource": "*"
    },
    {
      "Sid": "PassCoinOpsRuntimeRoleToEc2",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::${ACCOUNT_ID}:role/${APP_ROLE_NAME}",
      "Condition": {"StringEquals": {"iam:PassedToService": "ec2.amazonaws.com"}}
    }
  ]
}
JSON

cat > "$TMP_DIR/app-runtime-trust.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Service": "ec2.amazonaws.com"},
      "Action": "sts:AssumeRole"
    }
  ]
}
JSON

cat > "$TMP_DIR/app-runtime-inline-policy.json" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ReadCoinOpsSecrets",
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
      "Resource": "arn:aws:secretsmanager:${AWS_REGION}:${ACCOUNT_ID}:secret:${NAME_PREFIX}/*"
    },
    {
      "Sid": "UseCoinOpsQueues",
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage",
        "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes", "sqs:GetQueueUrl"
      ],
      "Resource": "arn:aws:sqs:${AWS_REGION}:${ACCOUNT_ID}:${NAME_PREFIX}-*"
    }
  ]
}
JSON

cleanup_old_queue_iam

ensure_service_linked_role "elasticloadbalancing.amazonaws.com" "AWSServiceRoleForElasticLoadBalancing"
ensure_service_linked_role "elasticache.amazonaws.com" "AWSServiceRoleForElastiCache"
ensure_service_linked_role "rds.amazonaws.com" "AWSServiceRoleForRDS"

if ! aws_admin iam get-role --role-name "$APP_ROLE_NAME" >/dev/null 2>&1; then
  aws_admin iam create-role \
    --role-name "$APP_ROLE_NAME" \
    --assume-role-policy-document "file://$TMP_DIR/app-runtime-trust.json" >/dev/null
  echo "Created role: $APP_ROLE_NAME"
else
  echo "Role exists: $APP_ROLE_NAME"
fi

aws_admin iam put-role-policy \
  --role-name "$APP_ROLE_NAME" \
  --policy-name "${NAME_PREFIX}-app-runtime-inline" \
  --policy-document "file://$TMP_DIR/app-runtime-inline-policy.json"

if ! aws_admin iam get-instance-profile --instance-profile-name "$APP_INSTANCE_PROFILE_NAME" >/dev/null 2>&1; then
  aws_admin iam create-instance-profile --instance-profile-name "$APP_INSTANCE_PROFILE_NAME" >/dev/null
  echo "Created instance profile: $APP_INSTANCE_PROFILE_NAME"
else
  echo "Instance profile exists: $APP_INSTANCE_PROFILE_NAME"
fi

PROFILE_ROLE="$(aws_admin iam get-instance-profile \
  --instance-profile-name "$APP_INSTANCE_PROFILE_NAME" \
  --query "InstanceProfile.Roles[?RoleName=='${APP_ROLE_NAME}'].RoleName | [0]" \
  --output text)"

if [ "$PROFILE_ROLE" = "None" ] || [ -z "$PROFILE_ROLE" ]; then
  aws_admin iam add-role-to-instance-profile \
    --instance-profile-name "$APP_INSTANCE_PROFILE_NAME" \
    --role-name "$APP_ROLE_NAME"
  echo "Attached role $APP_ROLE_NAME to instance profile $APP_INSTANCE_PROFILE_NAME"
fi

ensure_policy "${NAME_PREFIX}-terraform-state" "$TMP_DIR/state-policy.json"
ensure_policy "${NAME_PREFIX}-terraform-network-compute-lb" "$TMP_DIR/network-compute-lb-policy.json"
ensure_policy "${NAME_PREFIX}-terraform-data-runtime" "$TMP_DIR/data-runtime-policy.json"
ensure_policy "${NAME_PREFIX}-terraform-pass-runtime-role" "$TMP_DIR/pass-role-policy.json"

echo "Bootstrap complete. Normal Terraform should use IAM user $IAM_USER without admin permissions."
