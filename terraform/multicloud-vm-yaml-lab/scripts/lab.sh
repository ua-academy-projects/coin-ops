#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$ROOT_DIR/../.." && pwd)"
ANSIBLE_INVENTORY_OUT="${ANSIBLE_INVENTORY_OUT:-$REPO_ROOT/ansible/inventory.cloud}"
BACKEND_CONFIG="${BACKEND_CONFIG:-backend.hcl}"
AUTO_APPROVE="${AUTO_APPROVE:-false}"
LOAD_ENV="${LOAD_ENV:-true}"

CONFIG_FILE="$ROOT_DIR/config/lab.yaml"

yaml_cloud_value() {
  local cloud="$1"
  local key="$2"
  awk -v cloud="$cloud" -v key="$key" '
    /^clouds:[[:space:]]*$/ { in_clouds=1; next }
    in_clouds && $0 ~ "^[[:space:]]{2}" cloud ":[[:space:]]*$" { in_target=1; next }
    in_clouds && in_target && $0 ~ "^[[:space:]]{4}" key ":[[:space:]]*" {
      sub("^[[:space:]]{4}" key ":[[:space:]]*", "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
    in_clouds && in_target && $0 ~ "^[[:space:]]{2}[[:alnum:]_-]+:[[:space:]]*$" { in_target=0 }
    in_clouds && $0 !~ "^[[:space:]]" { in_clouds=0; in_target=0 }
  ' "$CONFIG_FILE"
}

yaml_secret_prefix() {
  awk '
    /^secrets:[[:space:]]*$/ { in_secrets=1; next }
    in_secrets && /^[[:space:]]{2}prefix:[[:space:]]*/ {
      sub(/^[[:space:]]{2}prefix:[[:space:]]*/, "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
    in_secrets && $0 !~ "^[[:space:]]" { in_secrets=0 }
  ' "$CONFIG_FILE"
}

yaml_secret_item() {
  local item="$1"
  awk -v item="$item" '
    /^secrets:[[:space:]]*$/ { in_secrets=1; next }
    in_secrets && /^[[:space:]]{2}items:[[:space:]]*$/ { in_items=1; next }
    in_secrets && in_items && $0 ~ "^[[:space:]]{4}" item ":[[:space:]]*" {
      sub("^[[:space:]]{4}" item ":[[:space:]]*", "")
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      print
      exit
    }
    in_secrets && $0 !~ "^[[:space:]]" { in_secrets=0; in_items=0 }
  ' "$CONFIG_FILE"
}


read_cloud() {
  awk -F: '/^cloud:[[:space:]]*/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$ROOT_DIR/config/lab.yaml"
}

read_runtime_mode() {
  awk '
    /^runtime:[[:space:]]*$/ { in_runtime=1; next }
    in_runtime && /^[^[:space:]]/ { in_runtime=0 }
    in_runtime && /^[[:space:]]+mode:[[:space:]]*/ { sub(/^[[:space:]]+mode:[[:space:]]*/, ""); gsub(/[[:space:]]/, ""); print; exit }
  ' "$ROOT_DIR/config/lab.yaml"
}

normalize_runtime_mode() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '-' '_'
}

CLOUD="${CLOUD:-$(read_cloud)}"
RUNTIME_MODE="${RUNTIME_MODE:-$(read_runtime_mode)}"
RUNTIME_MODE="$(normalize_runtime_mode "${RUNTIME_MODE:-external}")"
LAB_WORKSPACE="${LAB_WORKSPACE:-$([ "$RUNTIME_MODE" = "cloud_native" ] && printf '%s-cloud-native' "$CLOUD" || printf '%s' "$CLOUD")}"

AWS_PROFILE_NAME="${AWS_PROFILE:-$(yaml_cloud_value aws profile)}"
LOCATION="${LOCATION:-$(awk -F: '/^location:[[:space:]]*/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$CONFIG_FILE")}"
export LOCATION="${LOCATION:-eu_central}"
AWS_REGION_NAME="${AWS_REGION:-$(awk '
  /^catalog:[[:space:]]*$/ { in_catalog=1; next }
  in_catalog && /^[[:space:]]{2}locations:[[:space:]]*$/ { in_locations=1; next }
  in_locations && $0 ~ "^[[:space:]]{4}" ENVIRON["LOCATION"] ":[[:space:]]*$" { in_location=1; next }
  in_location && /^[[:space:]]{6}aws:[[:space:]]*$/ { in_aws=1; next }
  in_aws && /^[[:space:]]{8}region:[[:space:]]*/ { sub(/^[[:space:]]{8}region:[[:space:]]*/, ""); print; exit }
' "$CONFIG_FILE")}"
GCP_PROJECT_ID="${GCP_PROJECT_ID:-$(yaml_cloud_value gcp project_id)}"
NAME_PREFIX="$(awk -F: '/^name_prefix:[[:space:]]*/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$CONFIG_FILE")"
SECRET_PREFIX="${SECRET_PREFIX:-$(yaml_secret_prefix)}"
SECRET_PREFIX="${SECRET_PREFIX:-$NAME_PREFIX}"
APP_INSTANCE_PROFILE_NAME="${APP_INSTANCE_PROFILE_NAME:-$(yaml_cloud_value aws app_instance_profile_name)}"
APP_INSTANCE_PROFILE_NAME="${APP_INSTANCE_PROFILE_NAME:-${NAME_PREFIX}-app-runtime-profile}"


usage() {
  cat <<USAGE
Usage: ./scripts/lab.sh <command>

Commands:
  doctor     check selected cloud credentials, bootstrap, and secret values
  secrets push  push local .env/exported secret values to cloud secret manager
  init       terraform init + select/create workspace from config/lab.yaml cloud/runtime
  plan       init, then terraform plan
  apply      init, terraform apply, then regenerate SSH config + Ansible inventory
  outputs    regenerate SSH config + Ansible inventory from current Terraform outputs
  ping       ansible ping all cloud hosts through generated inventory
  deploy     run Ansible provision + deploy using generated inventory
  full       apply, regenerate outputs, then deploy

Useful env vars:
  AUTO_APPROVE=true       pass -auto-approve to terraform apply
  LAB_WORKSPACE=...      override auto workspace; cloud-native defaults to <cloud>-cloud-native
  LOAD_ENV=false          do not source repo .env if present
  SSH_KEY_PATH=...        required for deploy
  DB_PASSWORD=...         local source for secrets push and TF_VAR_db_password
  RABBITMQ_PASSWORD=...   local source for secrets push in external/postgres mode
  GHCR_TOKEN=...          optional local source for secrets push
  config/lab.yaml runtime.mode controls external/postgres/cloud-native

Examples:
  ./scripts/lab.sh plan
  AUTO_APPROVE=true ./scripts/lab.sh apply
  SSH_KEY_PATH=~/.ssh/coinops_gcp_jump DB_PASSWORD=... ./scripts/lab.sh deploy
  AUTO_APPROVE=true SSH_KEY_PATH=~/.ssh/coinops_gcp_jump DB_PASSWORD=... ./scripts/lab.sh full
USAGE
}

load_env_file() {
  if [ "$LOAD_ENV" = "true" ] && [ -f "$REPO_ROOT/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$REPO_ROOT/.env"
    set +a
  fi
}



aws_cli() {
  aws --profile "$AWS_PROFILE_NAME" --region "$AWS_REGION_NAME" "$@"
}

gcp_secret_id() {
  local item="$1"
  printf '%s-%s' "$SECRET_PREFIX" "$item" | tr '/_' '--'
}

aws_secret_name() {
  local item="$1"
  printf '%s/%s' "${SECRET_PREFIX%/}" "$item"
}

secret_item_name() {
  local key="$1"
  local fallback="$2"
  local value
  value="$(yaml_secret_item "$key")"
  printf '%s' "${value:-$fallback}"
}

push_aws_secret() {
  local name="$1"
  local value="$2"
  if aws_cli secretsmanager describe-secret --secret-id "$name" >/dev/null 2>&1; then
    aws_cli secretsmanager put-secret-value --secret-id "$name" --secret-string "$value" --query VersionId --output text >/dev/null
  else
    aws_cli secretsmanager create-secret --name "$name" --secret-string "$value" --query ARN --output text >/dev/null
  fi
  echo "Pushed AWS secret: $name"
}

push_gcp_secret() {
  local secret_id="$1"
  local value="$2"
  if ! gcloud secrets describe "$secret_id" --project "$GCP_PROJECT_ID" >/dev/null 2>&1; then
    gcloud secrets create "$secret_id" --project "$GCP_PROJECT_ID" --replication-policy automatic >/dev/null
  fi
  printf '%s' "$value" | gcloud secrets versions add "$secret_id" --project "$GCP_PROJECT_ID" --data-file - >/dev/null
  echo "Pushed GCP secret: $secret_id"
}

push_secret_value() {
  local key="$1"
  local env_name="$2"
  local fallback_name="$3"
  local required="${4:-true}"
  local value="${!env_name:-}"
  local item_name
  item_name="$(secret_item_name "$key" "$fallback_name")"
  if [ -z "$value" ]; then
    if [ "$required" = "true" ]; then
      echo "Missing $env_name. Set it in .env or export it before './scripts/lab.sh secrets push'." >&2
      exit 1
    fi
    echo "Skipping optional secret $key because $env_name is empty."
    return
  fi
  case "$CLOUD" in
    aws) push_aws_secret "$(aws_secret_name "$item_name")" "$value" ;;
    gcp) push_gcp_secret "$(gcp_secret_id "$item_name")" "$value" ;;
    *) echo "Unsupported cloud: $CLOUD" >&2; exit 1 ;;
  esac
}

ensure_secret_containers() {
  terraform_init
  cd "$ROOT_DIR"
  case "$CLOUD" in
    aws) terraform apply -target='module.aws[0].module.secrets' -auto-approve ;;
    gcp) terraform apply -target='module.gcp[0].module.secrets' -auto-approve ;;
  esac
}

secrets_push() {
  load_env_file
  ensure_secret_containers
  push_secret_value db_password DB_PASSWORD db-password true
  if [ "$RUNTIME_MODE" != "cloud_native" ]; then
    push_secret_value rabbitmq_password RABBITMQ_PASSWORD rabbitmq-password true
  fi
  push_secret_value ghcr_token GHCR_TOKEN ghcr-token false
}

check_secret_value_exists() {
  local key="$1"
  local fallback_name="$2"
  local item_name
  item_name="$(secret_item_name "$key" "$fallback_name")"
  case "$CLOUD" in
    aws) aws_cli secretsmanager get-secret-value --secret-id "$(aws_secret_name "$item_name")" >/dev/null ;;
    gcp) gcloud secrets versions access latest --secret "$(gcp_secret_id "$item_name")" --project "$GCP_PROJECT_ID" >/dev/null ;;
  esac
}

doctor() {
  local failed=false
  echo "Cloud: $CLOUD"
  echo "Workspace: $LAB_WORKSPACE"
  case "$CLOUD" in
    aws)
      aws_cli sts get-caller-identity --query Arn --output text
      for role in AWSServiceRoleForElasticLoadBalancing AWSServiceRoleForElastiCache AWSServiceRoleForRDS; do
        if aws --profile "$AWS_PROFILE_NAME" iam get-role --role-name "$role" >/dev/null 2>&1; then
          echo "OK service-linked role: $role"
        else
          echo "Missing service-linked role: $role. Run aws-iam/bootstrap.sh once with an admin profile."
          failed=true
        fi
      done
      if aws --profile "$AWS_PROFILE_NAME" iam get-instance-profile --instance-profile-name "$APP_INSTANCE_PROFILE_NAME" >/dev/null 2>&1; then
        echo "OK app instance profile: $APP_INSTANCE_PROFILE_NAME"
      else
        echo "Missing app instance profile: $APP_INSTANCE_PROFILE_NAME. Run aws-iam/bootstrap.sh once with an admin profile."
        failed=true
      fi
      ;;
    gcp)
      gcloud projects describe "$GCP_PROJECT_ID" --format='value(projectId)'
      ;;
  esac
  secret_specs=("db_password db-password")
  if [ "$RUNTIME_MODE" != "cloud_native" ]; then
    secret_specs+=("rabbitmq_password rabbitmq-password")
  fi
  for spec in "${secret_specs[@]}"; do
    set -- $spec
    if check_secret_value_exists "$1" "$2" >/dev/null 2>&1; then
      echo "OK secret value: $1"
    else
      echo "Missing secret value: $1. Run './scripts/lab.sh secrets push'."
    fi
  done
  if [ "$failed" = "true" ]; then
    exit 1
  fi
}

terraform_init() {
  load_env_file
  if [ -n "${DB_PASSWORD:-}" ]; then
    export TF_VAR_db_password="$DB_PASSWORD"
  fi
  cd "$ROOT_DIR"
  terraform init -backend-config="$BACKEND_CONFIG" -reconfigure
  terraform workspace select "$LAB_WORKSPACE" || terraform workspace new "$LAB_WORKSPACE"
}

terraform_apply() {
  cd "$ROOT_DIR"
  if [ "$AUTO_APPROVE" = "true" ]; then
    terraform apply -auto-approve
  else
    terraform apply
  fi
}

write_outputs() {
  cd "$ROOT_DIR"
  CLOUD="$CLOUD" "$ROOT_DIR/scripts/post-apply.sh"
}

ansible_deploy() {
  load_env_file
  : "${SSH_KEY_PATH:?Set SSH_KEY_PATH or put it in .env}"
  export RUNTIME_BACKEND="$RUNTIME_MODE"
  cd "$REPO_ROOT"
  ansible-playbook -i "$ANSIBLE_INVENTORY_OUT" ansible/cloud-provision.yml
  ansible-playbook -i "$ANSIBLE_INVENTORY_OUT" ansible/cloud-deploy.yml
}

cmd="${1:-}"
case "$cmd" in
  doctor)
    doctor
    ;;
  secrets)
    case "${2:-}" in
      push) secrets_push ;;
      *) echo "Usage: ./scripts/lab.sh secrets push" >&2; exit 2 ;;
    esac
    ;;
  init)
    terraform_init
    ;;
  plan)
    terraform_init
    cd "$ROOT_DIR"
    terraform plan
    ;;
  apply)
    terraform_init
    terraform_apply
    write_outputs
    ;;
  outputs)
    write_outputs
    ;;
  ping)
    cd "$REPO_ROOT"
    ansible -i "$ANSIBLE_INVENTORY_OUT" all -m ping
    ;;
  deploy)
    write_outputs
    ansible_deploy
    ;;
  full)
    terraform_init
    terraform_apply
    write_outputs
    ansible_deploy
    ;;
  -h|--help|help|"")
    usage
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    usage >&2
    exit 2
    ;;
esac