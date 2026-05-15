#!/bin/bash
set -euo pipefail

# Bootstrap script to set up AWS environment for Terraform.
# This prepares AWS as a possible full control-plane by creating state storage,
# native S3 lockfile support, IAM credentials, and local operator credentials.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MAPPING_PATH="${SCRIPT_DIR}/config/cloud_mappings.json"
CONFIG_DIR="${SCRIPT_DIR}/config"
BACKEND_TEMPLATE_PATH="${SCRIPT_DIR}/backends/backend.aws.tf.tmpl"
BACKEND_ACTIVE_PATH="${SCRIPT_DIR}/backend.active.tf"
CONFIG_FILES=(clouds.json general.json deploy.json dns.json instances.json)

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
for name in ("clouds.json", "general.json", "deploy.json", "dns.json", "instances.json"):
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
REGION_PROFILE="$(read_config 'data["general"]["region_profile"]')"
REGION="$(python3 -c 'import json,sys; data=json.load(open(sys.argv[1], encoding="utf-8")); print(data["regions"]["aws"][sys.argv[2]]["region"])' "${MAPPING_PATH}" "${REGION_PROFILE}")"
STATE_BUCKET_PREFIX="$(read_config 'data["clouds"]["backends"]["aws"].get("bucket_prefix", "coinops-terraform-state")')"
STATE_KEY="$(read_config 'data["clouds"]["backends"]["aws"].get("key", "infra/state/terraform.tfstate")')"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
BUCKET_NAME="${STATE_BUCKET_PREFIX}-${ACCOUNT_ID}-${REGION}"
GENERATED_AWS_ENV_PATH="${REPO_ROOT}/local/generated-aws-env.sh"
SSH_PUBLIC_KEY_PATH="${HOME}/.ssh/ssh-key-coin-ops.pub"

echo "Starting AWS bootstrap process in account ${ACCOUNT_ID}, region ${REGION}"

echo "Ensuring IAM User exists: $IAM_USER_NAME"
if ! aws iam get-user --user-name "$IAM_USER_NAME" > /dev/null 2>&1; then
  aws iam create-user --user-name "$IAM_USER_NAME" > /dev/null
fi

echo "Assigning IAM policies..."
for policy in \
  "arn:aws:iam::aws:policy/AmazonEC2FullAccess" \
  "arn:aws:iam::aws:policy/AmazonVPCFullAccess" \
  "arn:aws:iam::aws:policy/AmazonS3FullAccess"
do
  aws iam attach-user-policy --user-name "$IAM_USER_NAME" --policy-arn "$policy" || true
done

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

echo "Generating AWS access key..."
CREDENTIALS="$(aws iam create-access-key --user-name "$IAM_USER_NAME" --output text --query 'AccessKey.[AccessKeyId,SecretAccessKey]')"
AWS_ACCESS_KEY_ID="$(echo "$CREDENTIALS" | awk '{print $1}')"
AWS_SECRET_ACCESS_KEY="$(echo "$CREDENTIALS" | awk '{print $2}')"

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
export SSH_KEY_PATH="\${HOME}/.ssh/ssh-key-coin-ops"
EOF
chmod 600 "$GENERATED_AWS_ENV_PATH"

echo "Bootstrap completed successfully!"
echo "Next steps:"
echo "  1. Source ${GENERATED_AWS_ENV_PATH}"
echo "  2. Review terraform/backend.active.tf and terraform/local.generated.auto.tfvars.json"
echo "  3. cd ${REPO_ROOT}/terraform && terraform init -reconfigure && terraform apply"
