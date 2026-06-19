#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash bootstrap-aws.sh [--activate-backend]

Bootstraps AWS account-side prerequisites for coin-ops:
  - creates or refreshes the Terraform IAM user
  - grants IAM policies needed for Terraform
  - creates or reuses the S3 state bucket
  - writes local AWS env / tfvars / ansible config helpers

Backend behavior:
  - if terraform/config/clouds.json sets clouds.control_plane = "aws",
    the script rewrites terraform/backend.active.tf
  - otherwise, backend.active.tf is left untouched unless you pass
    --activate-backend explicitly
EOF
}

ACTIVATE_BACKEND=false
if [[ "${1:-}" == "--activate-backend" ]]; then
  ACTIVATE_BACKEND=true
elif [[ -n "${1:-}" ]]; then
  usage
  exit 1
fi

# Bootstrap script to set up AWS environment for Terraform.
# This prepares AWS as a possible full control-plane by creating state storage,
# native S3 lockfile support, IAM credentials, and local AWS env files.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MAPPING_PATH="${SCRIPT_DIR}/config/cloud_mappings.json"
CONFIG_DIR="${SCRIPT_DIR}/config"
BACKEND_TEMPLATE_PATH="${SCRIPT_DIR}/backends/backend.aws.tf.tmpl"
BACKEND_ACTIVE_PATH="${SCRIPT_DIR}/backend.active.tf"
CONFIG_FILES=(clouds.json general.json deploy.json database.json dns.json secrets.json instances.json observability.json)

if [ ! -f "${MAPPING_PATH}" ]; then
  echo "Missing cloud mappings file: ${MAPPING_PATH}"
  exit 1
fi

for config_file in "${CONFIG_FILES[@]}"; do
  if [ ! -f "${CONFIG_DIR}/${config_file}" ]; then
    echo "Missing Terraform config file: ${CONFIG_DIR}/${config_file}"
    exit 1
  fi
done

if [ ! -f "${BACKEND_TEMPLATE_PATH}" ]; then
  echo "Missing backend template file: ${BACKEND_TEMPLATE_PATH}"
  exit 1
fi

read_config() {
  python3 - "$CONFIG_DIR" "$1" <<'PY'
import json
import pathlib
import sys

config_dir = pathlib.Path(sys.argv[1])
expression = sys.argv[2]
data = {}
for name in ("clouds.json", "general.json", "deploy.json", "database.json", "dns.json", "secrets.json", "instances.json", "observability.json"):
    with (config_dir / name).open(encoding="utf-8") as handle:
        data.update(json.load(handle))

value = eval(expression, {"__builtins__": {}}, {"data": data})
if isinstance(value, bool):
    print(str(value).lower())
else:
    print(value)
PY
}

IAM_USER_NAME="$(read_config 'data["clouds"]["providers"]["aws"]["terraform_identity"]["name"]')"
PROJECT_NAME="$(read_config 'data["general"].get("project_name", "coin-ops")')"
CONTROL_PLANE="$(read_config 'data["clouds"]["control_plane"]')"
REGION_PROFILE="$(read_config 'data["general"]["region_profile"]')"
REGION="$(python3 -c 'import json,sys; data=json.load(open(sys.argv[1], encoding="utf-8")); print(data["regions"]["aws"][sys.argv[2]]["region"])' "${MAPPING_PATH}" "${REGION_PROFILE}")"
STATE_BUCKET_PREFIX="$(read_config 'data["clouds"]["backends"]["aws"].get("bucket_prefix", "coinops-terraform-state")')"
STATE_KEY="$(read_config 'data["clouds"]["backends"]["aws"].get("key", "infra/state/terraform.tfstate")')"
EKS_CLUSTER_NAME="$(read_config 'data["deploy"].get("eks", {}).get("cluster_name", data["general"].get("project_name", "coin-ops") + "-eks")')"
EKS_NODE_GROUP_NAME="$(read_config 'data["deploy"].get("eks", {}).get("node_group", {}).get("name", "system")')"
CONTAINER_LOG_GROUP_NAME="$(read_config 'data.get("observability", {}).get("logs", {}).get("container_log_group_name", "/" + data["general"].get("project_name", "coin-ops") + "/kubernetes/containers")')"

CALLER_IDENTITY="$(aws sts get-caller-identity --output json)"
ACCOUNT_ID="$(python3 - <<'PY' "$CALLER_IDENTITY"
import json
import sys

print(json.loads(sys.argv[1])["Account"])
PY
)"
CALLER_ARN="$(python3 - <<'PY' "$CALLER_IDENTITY"
import json
import sys

print(json.loads(sys.argv[1])["Arn"])
PY
)"
TARGET_USER_ARN="arn:aws:iam::${ACCOUNT_ID}:user/${IAM_USER_NAME}"
SCOPED_MANAGEMENT_POLICY_NAME="coinops-terraform-scoped-management"
SCOPED_MANAGEMENT_POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${SCOPED_MANAGEMENT_POLICY_NAME}"
LEGACY_SCOPED_INLINE_POLICY_NAME="coinops-cnpg-backup-identity-management"
CNPG_BACKUP_USER_NAME="$(python3 - <<'PY' "${PROJECT_NAME}"
import sys

print((sys.argv[1].replace("_", "-").lower() + "-cnpg-backup")[:64])
PY
)"
CNPG_BACKUP_USER_ARN="arn:aws:iam::${ACCOUNT_ID}:user/${CNPG_BACKUP_USER_NAME}"
EC2_OBSERVABILITY_ROLE_NAME="${PROJECT_NAME}-ec2-observability"
EC2_OBSERVABILITY_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${EC2_OBSERVABILITY_ROLE_NAME}"
EC2_OBSERVABILITY_INSTANCE_PROFILE_ARN="arn:aws:iam::${ACCOUNT_ID}:instance-profile/${EC2_OBSERVABILITY_ROLE_NAME}"
EKS_CLUSTER_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${EKS_CLUSTER_NAME}-cluster"
EKS_NODE_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${EKS_CLUSTER_NAME}-${EKS_NODE_GROUP_NAME}-node"
EKS_EBS_CSI_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${EKS_CLUSTER_NAME}-ebs-csi"
EKS_OIDC_PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.${REGION}.amazonaws.com/id/*"
EKS_CLUSTER_ARN="arn:aws:eks:${REGION}:${ACCOUNT_ID}:cluster/${EKS_CLUSTER_NAME}"
CONTAINER_LOG_GROUP_RESOURCE_ARNS="$(python3 - <<'PY' "${REGION}" "${ACCOUNT_ID}" "${CONTAINER_LOG_GROUP_NAME}" "/${PROJECT_NAME}/k3s/containers"
import json
import sys

region, account_id = sys.argv[1], sys.argv[2]
log_group_names = sys.argv[3:]
arns = []
for name in log_group_names:
    base_arn = f"arn:aws:logs:{region}:{account_id}:log-group:{name}"
    arns.extend([base_arn, f"{base_arn}:*"])
print(json.dumps(list(dict.fromkeys(arns))))
PY
)"
OBSERVABILITY_ALERTS_TOPIC_ARN="arn:aws:sns:${REGION}:${ACCOUNT_ID}:${PROJECT_NAME}-observability-alerts"
OBSERVABILITY_ALARM_ARN="arn:aws:cloudwatch:${REGION}:${ACCOUNT_ID}:alarm:${PROJECT_NAME}-*"
CLOUDWATCH_AGENT_PARAMETER_NAME="/${PROJECT_NAME}/cloudwatch-agent/linux"
CLOUDWATCH_AGENT_PARAMETER_ARN="arn:aws:ssm:${REGION}:${ACCOUNT_ID}:parameter${CLOUDWATCH_AGENT_PARAMETER_NAME}"
RUNNING_AS_TARGET_USER=false
if [ "$CALLER_ARN" = "$TARGET_USER_ARN" ]; then
  RUNNING_AS_TARGET_USER=true
fi
BUCKET_NAME="${STATE_BUCKET_PREFIX}-${ACCOUNT_ID}-${REGION}"
GENERATED_AWS_ENV_PATH="${REPO_ROOT}/local/generated-aws-env.sh"
GENERATED_ACTIVE_ENV_PATH="${REPO_ROOT}/local/generated-env.sh"
SSH_PUBLIC_KEY_PATH="${HOME}/.ssh/ssh-key-coin-ops.pub"

if [[ "${CONTROL_PLANE}" == "aws" ]]; then
  ACTIVATE_BACKEND=true
fi

echo "Starting AWS bootstrap process in account ${ACCOUNT_ID}, region ${REGION}"
echo "Active AWS identity: ${CALLER_ARN}"

build_scoped_management_policy_document() {
  python3 - <<'PY' "${CNPG_BACKUP_USER_ARN}" "${TARGET_USER_ARN}" "${EC2_OBSERVABILITY_ROLE_ARN}" "${EC2_OBSERVABILITY_INSTANCE_PROFILE_ARN}" "${CONTAINER_LOG_GROUP_RESOURCE_ARNS}" "${OBSERVABILITY_ALERTS_TOPIC_ARN}" "${OBSERVABILITY_ALARM_ARN}" "${CLOUDWATCH_AGENT_PARAMETER_ARN}" "${EKS_CLUSTER_ROLE_ARN}" "${EKS_NODE_ROLE_ARN}" "${EKS_EBS_CSI_ROLE_ARN}" "${EKS_OIDC_PROVIDER_ARN}" "${EKS_CLUSTER_ARN}"
import json
import sys

cnpg_backup_user_arn = sys.argv[1]
target_user_arn = sys.argv[2]
ec2_observability_role_arn = sys.argv[3]
ec2_observability_instance_profile_arn = sys.argv[4]
container_log_group_resource_arns = json.loads(sys.argv[5])
observability_alerts_topic_arn = sys.argv[6]
observability_alarm_arn = sys.argv[7]
cloudwatch_agent_parameter_arn = sys.argv[8]
eks_role_arns = sys.argv[9:12]
eks_oidc_provider_arn = sys.argv[12]
eks_cluster_arn = sys.argv[13]
print(json.dumps({
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "ManageCnpgBackupIamUser",
            "Effect": "Allow",
            "Action": [
                "iam:CreateUser",
                "iam:DeleteUser",
                "iam:GetUser",
                "iam:TagUser",
                "iam:UntagUser",
                "iam:ListUserTags",
                "iam:ListGroupsForUser",
                "iam:ListAttachedUserPolicies",
                "iam:PutUserPolicy",
                "iam:GetUserPolicy",
                "iam:DeleteUserPolicy",
                "iam:ListUserPolicies",
                "iam:CreateAccessKey",
                "iam:DeleteAccessKey",
                "iam:GetAccessKeyLastUsed",
                "iam:ListAccessKeys",
                "iam:UpdateAccessKey"
            ],
            "Resource": cnpg_backup_user_arn
        },
        {
            "Sid": "ManageEc2ObservabilityRole",
            "Effect": "Allow",
            "Action": [
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:GetRole",
                "iam:TagRole",
                "iam:UntagRole",
                "iam:ListRoleTags",
                "iam:AttachRolePolicy",
                "iam:DetachRolePolicy",
                "iam:ListAttachedRolePolicies",
                "iam:ListRolePolicies",
                "iam:GetRolePolicy",
                "iam:DeleteRolePolicy",
                "iam:ListInstanceProfilesForRole"
            ],
            "Resource": ec2_observability_role_arn
        },
        {
            "Sid": "ManageEksIamRoles",
            "Effect": "Allow",
            "Action": [
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:GetRole",
                "iam:TagRole",
                "iam:UntagRole",
                "iam:ListRoleTags",
                "iam:AttachRolePolicy",
                "iam:DetachRolePolicy",
                "iam:ListAttachedRolePolicies",
                "iam:ListRolePolicies",
                "iam:ListInstanceProfilesForRole",
                "iam:GetRolePolicy",
                "iam:PutRolePolicy",
                "iam:DeleteRolePolicy",
                "iam:UpdateAssumeRolePolicy"
            ],
            "Resource": eks_role_arns
        },
        {
            "Sid": "PassEksIamRoles",
            "Effect": "Allow",
            "Action": [
                "iam:PassRole"
            ],
            "Resource": eks_role_arns,
            "Condition": {
                "StringEquals": {
                    "iam:PassedToService": [
                        "eks.amazonaws.com",
                        "ec2.amazonaws.com"
                    ]
                }
            }
        },
        {
            "Sid": "ManageEksOidcProvider",
            "Effect": "Allow",
            "Action": [
                "iam:CreateOpenIDConnectProvider",
                "iam:DeleteOpenIDConnectProvider",
                "iam:GetOpenIDConnectProvider",
                "iam:TagOpenIDConnectProvider",
                "iam:UntagOpenIDConnectProvider",
                "iam:ListOpenIDConnectProviderTags"
            ],
            "Resource": eks_oidc_provider_arn
        },
        {
            "Sid": "PassEc2ObservabilityRoleToEc2",
            "Effect": "Allow",
            "Action": [
                "iam:PassRole"
            ],
            "Resource": ec2_observability_role_arn,
            "Condition": {
                "StringEquals": {
                    "iam:PassedToService": "ec2.amazonaws.com"
                }
            }
        },
        {
            "Sid": "ManageEc2ObservabilityInstanceProfile",
            "Effect": "Allow",
            "Action": [
                "iam:CreateInstanceProfile",
                "iam:DeleteInstanceProfile",
                "iam:GetInstanceProfile",
                "iam:AddRoleToInstanceProfile",
                "iam:RemoveRoleFromInstanceProfile",
                "iam:TagInstanceProfile",
                "iam:UntagInstanceProfile",
                "iam:ListInstanceProfileTags"
            ],
            "Resource": ec2_observability_instance_profile_arn
        },
        {
            "Sid": "CreateAndListCloudWatchLogGroups",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:DescribeLogGroups"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ManageK3sContainerLogGroup",
            "Effect": "Allow",
            "Action": [
                "logs:DeleteLogGroup",
                "logs:PutRetentionPolicy",
                "logs:DeleteRetentionPolicy",
                "logs:PutMetricFilter",
                "logs:DeleteMetricFilter",
                "logs:DescribeMetricFilters",
                "logs:ListTagsForResource",
                "logs:TagResource",
                "logs:UntagResource"
            ],
            "Resource": container_log_group_resource_arns
        },
        {
            "Sid": "ManageObservabilityAlarms",
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutMetricAlarm",
                "cloudwatch:DeleteAlarms",
                "cloudwatch:DescribeAlarms",
                "cloudwatch:EnableAlarmActions",
                "cloudwatch:DisableAlarmActions",
                "cloudwatch:ListTagsForResource",
                "cloudwatch:TagResource",
                "cloudwatch:UntagResource"
            ],
            "Resource": observability_alarm_arn
        },
        {
            "Sid": "ReadCloudWatchMetricsForTerraformRefresh",
            "Effect": "Allow",
            "Action": [
                "cloudwatch:DescribeAlarms",
                "cloudwatch:ListMetrics"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ManageObservabilityDashboards",
            "Effect": "Allow",
            "Action": [
                "cloudwatch:PutDashboard",
                "cloudwatch:GetDashboard",
                "cloudwatch:DeleteDashboards",
                "cloudwatch:ListDashboards"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ManageObservabilitySnsTopic",
            "Effect": "Allow",
            "Action": [
                "sns:CreateTopic",
                "sns:DeleteTopic",
                "sns:GetTopicAttributes",
                "sns:SetTopicAttributes",
                "sns:ListTagsForResource",
                "sns:TagResource",
                "sns:UntagResource",
                "sns:Subscribe",
                "sns:Unsubscribe",
                "sns:GetSubscriptionAttributes",
                "sns:SetSubscriptionAttributes",
                "sns:ListSubscriptionsByTopic"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ListSnsForTerraformRefresh",
            "Effect": "Allow",
            "Action": [
                "sns:ListTopics",
                "sns:ListSubscriptions"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ManageCloudWatchAgentParameter",
            "Effect": "Allow",
            "Action": [
                "ssm:PutParameter",
                "ssm:GetParameter",
                "ssm:GetParameters",
                "ssm:DeleteParameter",
                "ssm:AddTagsToResource",
                "ssm:RemoveTagsFromResource",
                "ssm:ListTagsForResource"
            ],
            "Resource": cloudwatch_agent_parameter_arn
        },
        {
            "Sid": "DescribeCloudWatchAgentParameters",
            "Effect": "Allow",
            "Action": [
                "ssm:DescribeParameters"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ManageCloudWatchAgentAssociations",
            "Effect": "Allow",
            "Action": [
                "ssm:CreateAssociation",
                "ssm:DeleteAssociation",
                "ssm:UpdateAssociation",
                "ssm:DescribeAssociation",
                "ssm:ListAssociations",
                "ssm:AddTagsToResource",
                "ssm:RemoveTagsFromResource",
                "ssm:ListTagsForResource",
                "ssm:GetDocument",
                "ssm:DescribeDocument"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ReadOwnTerraformUserPolicies",
            "Effect": "Allow",
            "Action": [
                "iam:GetUser",
                "iam:GetUserPolicy",
                "iam:ListUserPolicies",
                "iam:ListAttachedUserPolicies"
            ],
            "Resource": target_user_arn
        },
        {
            "Sid": "ListIamResourcesForTerraformRefresh",
            "Effect": "Allow",
            "Action": [
                "iam:ListUsers",
                "iam:ListRoles",
                "iam:ListInstanceProfiles",
                "iam:ListPolicies"
            ],
            "Resource": "*"
        },
        {
            "Sid": "ManageEksCluster",
            "Effect": "Allow",
            "Action": "eks:*",
            "Resource": "*"
        }
    ]
}))
PY
}

put_scoped_iam_policy() {
  echo "Granting scoped IAM permissions for Terraform-managed identities..."
  local policy_document
  policy_document="$(build_scoped_management_policy_document)"

  if aws iam get-policy --policy-arn "$SCOPED_MANAGEMENT_POLICY_ARN" >/dev/null 2>&1; then
    local versions_to_delete
    versions_to_delete="$(aws iam list-policy-versions \
      --policy-arn "$SCOPED_MANAGEMENT_POLICY_ARN" \
      --query 'Versions[?IsDefaultVersion==`false`].VersionId' \
      --output text)"

    for version_id in $versions_to_delete; do
      aws iam delete-policy-version \
        --policy-arn "$SCOPED_MANAGEMENT_POLICY_ARN" \
        --version-id "$version_id" >/dev/null
    done

    aws iam create-policy-version \
      --policy-arn "$SCOPED_MANAGEMENT_POLICY_ARN" \
      --policy-document "$policy_document" \
      --set-as-default >/dev/null
  else
    aws iam create-policy \
      --policy-name "$SCOPED_MANAGEMENT_POLICY_NAME" \
      --policy-document "$policy_document" >/dev/null
  fi

  aws iam attach-user-policy \
    --user-name "$IAM_USER_NAME" \
    --policy-arn "$SCOPED_MANAGEMENT_POLICY_ARN" >/dev/null

  aws iam delete-user-policy \
    --user-name "$IAM_USER_NAME" \
    --policy-name "$LEGACY_SCOPED_INLINE_POLICY_NAME" >/dev/null 2>&1 || true
}

if [ "$RUNNING_AS_TARGET_USER" = true ]; then
  cat <<EOF >&2
The current credentials are for ${IAM_USER_NAME}. Bootstrap must refresh the
managed IAM policy ${SCOPED_MANAGEMENT_POLICY_NAME}, and this user cannot grant
itself new or updated IAM permissions.

  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  AWS_PROFILE=<admin-profile> bash terraform/bootstrap-aws.sh --activate-backend

Then source local/generated-env.sh again and rerun terraform apply.
EOF
  exit 1
else
  echo "Ensuring IAM User exists: $IAM_USER_NAME"
  if ! aws iam get-user --user-name "$IAM_USER_NAME" > /dev/null 2>&1; then
    if ! aws iam create-user --user-name "$IAM_USER_NAME" > /dev/null; then
      echo "Failed to create IAM user ${IAM_USER_NAME}."
      echo "Run bootstrap with an admin/operator AWS identity, or pre-create ${TARGET_USER_ARN} with the required policies."
      exit 1
    fi
  fi

  echo "Assigning IAM policies..."
  for policy in \
    "arn:aws:iam::aws:policy/AmazonEC2FullAccess" \
    "arn:aws:iam::aws:policy/AmazonVPCFullAccess" \
    "arn:aws:iam::aws:policy/AmazonS3FullAccess" \
    "arn:aws:iam::aws:policy/AmazonRDSFullAccess" \
    "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
  do
    aws iam attach-user-policy --user-name "$IAM_USER_NAME" --policy-arn "$policy" || true
  done

  put_scoped_iam_policy

  echo "Checking Terraform IAM access key capacity..."
  EXISTING_KEY_COUNT="$(aws iam list-access-keys --user-name "$IAM_USER_NAME" --query 'length(AccessKeyMetadata)' --output text)"
  if [ "$EXISTING_KEY_COUNT" -ge 2 ]; then
    echo "IAM user ${IAM_USER_NAME} already has ${EXISTING_KEY_COUNT} access keys."
    echo "Delete an old key with aws iam delete-access-key before rerunning bootstrap, or reuse local/generated-aws-env.sh."
    exit 1
  fi
fi

echo "Ensuring S3 state bucket exists: $BUCKET_NAME"
if ! aws s3api head-bucket --bucket "$BUCKET_NAME" > /dev/null 2>&1; then
  aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" > /dev/null
fi

echo "Enabling S3 bucket versioning and encryption..."
aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled
aws s3api put-bucket-encryption \
  --bucket "$BUCKET_NAME" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block \
  --bucket "$BUCKET_NAME" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

if [ "$RUNNING_AS_TARGET_USER" = true ]; then
  if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    echo "Cannot write generated env while running as ${IAM_USER_NAME} without AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY in the current environment."
    echo "Source the existing local/generated-aws-env.sh, or rerun bootstrap with an admin/operator identity to generate a new access key."
    exit 1
  fi
else
  echo "Generating AWS access key..."
  CREDENTIALS="$(aws iam create-access-key --user-name "$IAM_USER_NAME" --output text --query 'AccessKey.[AccessKeyId,SecretAccessKey]')"
  AWS_ACCESS_KEY_ID="$(echo "$CREDENTIALS" | awk '{print $1}')"
  AWS_SECRET_ACCESS_KEY="$(echo "$CREDENTIALS" | awk '{print $2}')"
fi

if [[ "${ACTIVATE_BACKEND}" == "true" ]]; then
  echo "Writing active Terraform backend at ${BACKEND_ACTIVE_PATH}..."
  python3 - <<'PY' "${BACKEND_TEMPLATE_PATH}" "${BACKEND_ACTIVE_PATH}" "${BUCKET_NAME}" "${STATE_KEY}" "${REGION}"
import pathlib
import sys

template_path, output_path, bucket, key, region = sys.argv[1:6]
content = pathlib.Path(template_path).read_text(encoding="utf-8")
content = content.replace("__AWS_STATE_BUCKET__", bucket)
content = content.replace("__AWS_STATE_KEY__", key)
content = content.replace("__AWS_STATE_REGION__", region)
pathlib.Path(output_path).write_text(content, encoding="utf-8")
PY
else
  echo "AWS account bootstrap completed without switching Terraform backend."
  echo "Leaving ${BACKEND_ACTIVE_PATH} untouched because clouds.control_plane=${CONTROL_PLANE}."
fi

LOCAL_TERRAFORM_TFVARS="${REPO_ROOT}/terraform/local.generated.auto.tfvars.json"
echo "Writing local Terraform config at ${LOCAL_TERRAFORM_TFVARS}..."
cat > "$LOCAL_TERRAFORM_TFVARS" << EOF
{
  "ssh_public_key_path": "${SSH_PUBLIC_KEY_PATH}"
}
EOF

LOCAL_ANSIBLE_CONFIG="${REPO_ROOT}/ansible/vars/local.generated.json"
echo "Writing optional local Ansible override at ${LOCAL_ANSIBLE_CONFIG}..."
cat > "$LOCAL_ANSIBLE_CONFIG" << EOF
{}
EOF

mkdir -p "${REPO_ROOT}/local"
echo "Writing generated AWS env at ${GENERATED_AWS_ENV_PATH}..."
cat > "$GENERATED_AWS_ENV_PATH" << EOF
#!/bin/bash
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}"
export TF_VAR_aws_region="${REGION}"
export AWS_REGION="\${TF_VAR_aws_region}"
export ANSIBLE_CONFIG="${REPO_ROOT}/ansible.cfg"
export COINOPS_REPO_ROOT="${REPO_ROOT}"
export SSH_KEY_PATH="\${HOME}/.ssh/ssh-key-coin-ops"
EOF
chmod 600 "$GENERATED_AWS_ENV_PATH"
cp "$GENERATED_AWS_ENV_PATH" "$GENERATED_ACTIVE_ENV_PATH"
chmod 600 "$GENERATED_ACTIVE_ENV_PATH"

BOOTSTRAP_TFVARS_EXAMPLE="${REPO_ROOT}/terraform/bootstrap.secrets.auto.tfvars.example"
echo "Writing bootstrap secrets example template at ${BOOTSTRAP_TFVARS_EXAMPLE}..."
cat > "$BOOTSTRAP_TFVARS_EXAMPLE" << EOF
db_password           = "CHANGE_ME"
rabbitmq_password     = "CHANGE_ME"
ghcr_token            = "CHANGE_ME"
cloudflare_api_token  = "CHANGE_ME"
tailscale_auth_key    = "CHANGE_ME"
github_oauth_client_id     = "CHANGE_ME"
github_oauth_client_secret = "CHANGE_ME"
EOF

BOOTSTRAP_TFVARS="${REPO_ROOT}/terraform/bootstrap.secrets.auto.tfvars"
if [ ! -f "$BOOTSTRAP_TFVARS" ]; then
  echo "Writing bootstrap secrets template at ${BOOTSTRAP_TFVARS}..."
  cat > "$BOOTSTRAP_TFVARS" << EOF
db_password          = "not_serious_just_a_placeholder"
rabbitmq_password    = "not_serious_just_a_placeholder"
ghcr_token           = "not_serious_just_a_placeholder"
cloudflare_api_token = "not_serious_just_a_placeholder"
github_oauth_client_id     = "not_serious_just_a_placeholder"
github_oauth_client_secret = "not_serious_just_a_placeholder"
EOF
fi

echo "Bootstrap completed successfully!"
echo "Next steps:"
echo "  1. Source ${GENERATED_AWS_ENV_PATH} (or local/generated-env.sh)"
echo "  2. Edit terraform/bootstrap.secrets.auto.tfvars if you need to seed/rotate secrets"
echo "  3. Review terraform/backend.active.tf and terraform/local.generated.auto.tfvars.json"
echo "  4. cd ${REPO_ROOT}/terraform && terraform init -reconfigure && terraform apply"
