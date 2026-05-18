#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bash full-destroy.sh --yes-really-destroy-stateful [--cloud all|gcp|aws|azure] [terraform destroy args...]

This script performs a deliberate teardown of compute and protected stateful
resources by:
  1. copying the Terraform root into a temporary directory
  2. removing hard destroy protections in the temporary copy only
  3. pre-cleaning provider-specific blockers for protected stateful resources
  4. running terraform destroy there against the same backend state

By default, it destroys resources across all enabled clouds. Use `--cloud` to
limit the destroy to a single cloud's Terraform modules.

The checked-in Terraform files remain unchanged.
EOF
}

if [[ "${1:-}" != "--yes-really-destroy-stateful" ]]; then
  usage
  exit 1
fi

shift

TARGET_CLOUD="all"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cloud)
      if [[ $# -lt 2 ]]; then
        echo "--cloud requires one of: all, gcp, aws, azure" >&2
        exit 1
      fi
      TARGET_CLOUD="$2"
      shift 2
      ;;
    --cloud=*)
      TARGET_CLOUD="${1#*=}"
      shift
      ;;
    *)
      break
      ;;
  esac
done

case "${TARGET_CLOUD}" in
  all|gcp|aws|azure)
    ;;
  *)
    echo "Unsupported --cloud value: ${TARGET_CLOUD}" >&2
    usage
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/coinops-full-destroy.XXXXXX")"
TMP_TERRAFORM_DIR="${TMP_ROOT}/terraform"

cleanup() {
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

mkdir -p "${TMP_TERRAFORM_DIR}"
cp -a "${TERRAFORM_DIR}/." "${TMP_TERRAFORM_DIR}/"
rm -rf "${TMP_TERRAFORM_DIR}/.terraform"

python3 - <<'PY' "${TMP_TERRAFORM_DIR}" "${TARGET_CLOUD}"
import json
import pathlib
import re
import shutil
import sys

terraform_dir = pathlib.Path(sys.argv[1])
target_cloud = sys.argv[2]

clouds = json.loads((terraform_dir / "config" / "clouds.json").read_text(encoding="utf-8")).get("clouds", {})
enabled_clouds = set(clouds.get("enabled", []))

locals_path = terraform_dir / "locals.tf"
locals_content = locals_path.read_text(encoding="utf-8")
for name in ("gcp", "aws", "azure"):
    locals_content = re.sub(
        rf"(\s*)read_{name}_secret_backend\s*=.*",
        rf"\1read_{name}_secret_backend = false",
        locals_content,
    )
    locals_content = re.sub(
        rf"(\s*){name}_db_secrets\s*=.*",
        rf"\1{name}_db_secrets  = {{}}",
        locals_content,
    )
    locals_content = re.sub(
        rf"(\s*){name}_app_secrets\s*=.*",
        rf"\1{name}_app_secrets = {{}}",
        locals_content,
    )
locals_path.write_text(locals_content, encoding="utf-8")

if "azure" not in enabled_clouds:
    shutil.rmtree(terraform_dir / "modules" / "cloud" / "azure", ignore_errors=True)

    disabled_module_dir = terraform_dir / "modules" / "cloud" / "disabled"
    disabled_module_dir.mkdir(parents=True, exist_ok=True)
    (disabled_module_dir / "main.tf").write_text("", encoding="utf-8")

    (terraform_dir / "azure.tf").write_text(
        """module "azure_network" {
  count  = 0
  source = "./modules/cloud/disabled"
}

module "azure_security_groups" {
  count  = 0
  source = "./modules/cloud/disabled"
}

module "azure_instances" {
  count  = 0
  source = "./modules/cloud/disabled"
}

module "azure_nat_route" {
  count  = 0
  source = "./modules/cloud/disabled"
}

module "azure_database" {
  count  = 0
  source = "./modules/cloud/disabled"
}

module "azure_secrets" {
  count  = 0
  source = "./modules/cloud/disabled"
}
""",
        encoding="utf-8",
    )

    providers_path = terraform_dir / "providers.tf"
    providers = providers_path.read_text(encoding="utf-8")
    providers = providers.replace(
        """    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
""",
        "",
    )
    providers = re.sub(
        r"\n\s*azurerm\s*=\s*\{\s*\n\s*source\s*=\s*\"hashicorp/azurerm\"\s*\n\s*version\s*=\s*\"[^\"]+\"\s*\n\s*\}",
        "",
        providers,
        flags=re.MULTILINE,
    )
    providers = re.sub(
        r"\nprovider\s+\"azurerm\"\s*\{\s*(?:features\s*\{\s*\}\s*)?(?:[^\n]*\n)*?\}\s*\n",
        "\n",
        providers,
        flags=re.MULTILINE,
    )
    providers_path.write_text(providers, encoding="utf-8")

    azurerm_refs = [
        str(path.relative_to(terraform_dir))
        for path in terraform_dir.rglob("*.tf")
        if ".terraform" not in path.parts and "azurerm" in path.read_text(encoding="utf-8", errors="ignore")
    ]
    if azurerm_refs:
        raise SystemExit("Azure provider references remain in full-destroy copy: " + ", ".join(azurerm_refs))

clouds_to_unguard = ["gcp", "aws", "azure"] if target_cloud == "all" else [target_cloud]
files = []
for name in clouds_to_unguard:
    files.extend(
        [
            terraform_dir / "modules" / "cloud" / name / "database" / "main.tf",
            terraform_dir / "modules" / "cloud" / name / "secrets" / "main.tf",
        ]
    )

lifecycle_pattern = re.compile(
    r"\n\s*lifecycle\s*\{\s*\n\s*prevent_destroy\s*=\s*true\s*\n\s*\}\s*\n",
    re.MULTILINE,
)

for path in files:
    if not path.exists():
        continue
    content = path.read_text(encoding="utf-8")
    content = lifecycle_pattern.sub("\n", content)
    if path.name == "main.tf" and path.parent.name == "database":
        content = content.replace("deletion_protection = true", "deletion_protection = false")
        content = content.replace("skip_final_snapshot         = false", "skip_final_snapshot         = true")
    path.write_text(content, encoding="utf-8")
PY

cat <<EOF
Prepared an isolated Terraform copy for full teardown:
  ${TMP_TERRAFORM_DIR}

Target cloud scope: ${TARGET_CLOUD}
Protected resources are unguarded only inside this temporary copy.
AWS RDS final snapshots are disabled in the temporary copy when AWS is targeted
to keep repeated lab teardowns deterministic.
Running terraform destroy against the existing backend state now...
EOF

cd "${TMP_TERRAFORM_DIR}"
terraform init

disable_aws_rds_deletion_protection() {
  if ! command -v aws >/dev/null 2>&1; then
    return 0
  fi

  local addresses=()
  mapfile -t addresses < <(terraform state list | grep 'aws_db_instance' || true)

  if [[ "${#addresses[@]}" -eq 0 ]]; then
    return 0
  fi

  echo "Disabling AWS RDS deletion protection for DB instances found in Terraform state..."

  local address identifier
  for address in "${addresses[@]}"; do
    identifier="$(
      terraform state show -no-color "${address}" \
        | awk -F'= ' '
            /^[[:space:]]*identifier[[:space:]]*=/ { gsub(/"/, "", $2); print $2; found=1; exit }
            /^[[:space:]]*id[[:space:]]*=/ { fallback=$2 }
            END {
              if (!found && fallback != "") {
                gsub(/"/, "", fallback)
                print fallback
              }
            }
          '
    )"

    if [[ -z "${identifier}" ]]; then
      echo "Could not determine DB instance identifier for ${address}; skipping."
      continue
    fi

    echo "Disabling deletion protection on ${identifier}..."
    local describe_error=""
    if ! describe_error="$(
      aws rds describe-db-instances \
        --db-instance-identifier "${identifier}" \
        2>&1 >/dev/null
    )"; then
      if grep -q "DBInstanceNotFound" <<<"${describe_error}"; then
        echo "DB instance ${identifier} was not found in AWS; skipping deletion protection disable."
        continue
      fi

      echo "${describe_error}" >&2
      return 1
    fi

    aws rds modify-db-instance \
      --db-instance-identifier "${identifier}" \
      --no-deletion-protection \
      --apply-immediately >/dev/null

    aws rds wait db-instance-available \
      --db-instance-identifier "${identifier}"
  done
}

force_delete_aws_secrets() {
  if ! command -v aws >/dev/null 2>&1; then
    return 0
  fi

  local addresses=()
  mapfile -t addresses < <(terraform state list | grep 'aws_secretsmanager_secret\.' || true)

  if [[ "${#addresses[@]}" -eq 0 ]]; then
    return 0
  fi

  echo "Force-deleting AWS Secrets Manager secrets found in Terraform state..."

  local address secret_name describe_error
  for address in "${addresses[@]}"; do
    secret_name="$(
      terraform state show -no-color "${address}" \
        | awk -F'= ' '
            /^[[:space:]]*name[[:space:]]*=/ { gsub(/"/, "", $2); print $2; exit }
          '
    )"

    if [[ -z "${secret_name}" ]]; then
      echo "Could not determine AWS secret name for ${address}; skipping."
      continue
    fi

    if ! describe_error="$(
      aws secretsmanager describe-secret \
        --secret-id "${secret_name}" \
        2>&1 >/dev/null
    )"; then
      if grep -Eqi 'ResourceNotFoundException|Secrets Manager can.t find the specified secret|not found' <<<"${describe_error}"; then
        echo "AWS secret ${secret_name} is already absent; pruning state."
        remove_state_if_present "${address}"
        continue
      fi

      echo "${describe_error}" >&2
      return 1
    fi

    echo "Force-deleting AWS secret ${secret_name}..."
    aws secretsmanager delete-secret \
      --secret-id "${secret_name}" \
      --force-delete-without-recovery >/dev/null

    remove_state_if_present "${address}"
  done
}

disable_gcp_sql_deletion_protection() {
  if ! command -v gcloud >/dev/null 2>&1; then
    return 0
  fi

  local addresses=()
  mapfile -t addresses < <(terraform state list | grep 'google_sql_database_instance' || true)

  if [[ "${#addresses[@]}" -eq 0 ]]; then
    return 0
  fi

  echo "Disabling GCP Cloud SQL deletion protection for instances found in Terraform state..."

  local address instance_name
  for address in "${addresses[@]}"; do
    instance_name="$(
      terraform state show -no-color "${address}" \
        | awk -F'= ' '
            /^[[:space:]]*name[[:space:]]*=/ { gsub(/"/, "", $2); print $2; exit }
          '
    )"

    if [[ -z "${instance_name}" ]]; then
      echo "Could not determine Cloud SQL instance name for ${address}; skipping."
      continue
    fi

    echo "Disabling deletion protection on ${instance_name}..."
    if ! gcloud sql instances describe "${instance_name}" >/dev/null 2>&1; then
      echo "Cloud SQL instance ${instance_name} was not found in GCP; skipping deletion protection disable."
      continue
    fi

    gcloud sql instances patch "${instance_name}" \
      --no-deletion-protection \
      --quiet >/dev/null
  done
}

wait_for_gcp_sql_instance_absent() {
  local instance_name="$1"
  local attempts=60

  for ((i = 1; i <= attempts; i++)); do
    if ! gcloud sql instances describe "${instance_name}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done

  echo "Timed out waiting for Cloud SQL instance ${instance_name} to disappear." >&2
  return 1
}

remove_state_if_present() {
  local address="$1"
  if terraform state show -no-color "${address}" >/dev/null 2>&1; then
    terraform state rm "${address}" >/dev/null
  fi
}

delete_gcp_sql_instances() {
  if ! command -v gcloud >/dev/null 2>&1; then
    return 0
  fi

  local addresses=()
  mapfile -t addresses < <(terraform state list | grep 'google_sql_database_instance' || true)

  if [[ "${#addresses[@]}" -eq 0 ]]; then
    return 0
  fi

  echo "Deleting GCP Cloud SQL instances found in Terraform state..."

  local address instance_name module_prefix sibling
  for address in "${addresses[@]}"; do
    instance_name="$(
      terraform state show -no-color "${address}" \
        | awk -F'= ' '
            /^[[:space:]]*name[[:space:]]*=/ { gsub(/"/, "", $2); print $2; exit }
          '
    )"

    if [[ -z "${instance_name}" ]]; then
      echo "Could not determine Cloud SQL instance name for ${address}; skipping."
      continue
    fi

    if gcloud sql instances describe "${instance_name}" >/dev/null 2>&1; then
      echo "Deleting Cloud SQL instance ${instance_name}..."
      gcloud sql instances patch "${instance_name}" \
        --no-deletion-protection \
        --quiet >/dev/null
      gcloud sql instances delete "${instance_name}" \
        --quiet >/dev/null
      wait_for_gcp_sql_instance_absent "${instance_name}"
    else
      echo "Cloud SQL instance ${instance_name} is already absent; pruning state."
    fi

    module_prefix="${address%.*.*}"
    remove_state_if_present "${address}"
    while IFS= read -r sibling; do
      [[ -n "${sibling}" ]] || continue
      remove_state_if_present "${sibling}"
    done < <(
      terraform state list | grep -F "${module_prefix}.google_sql_database." || true
      terraform state list | grep -F "${module_prefix}.google_sql_user." || true
      terraform state list | grep -F "${module_prefix}.random_id." || true
    )
  done
}

delete_gcp_private_service_access() {
  if ! command -v gcloud >/dev/null 2>&1; then
    return 0
  fi

  local connection_addresses=()
  mapfile -t connection_addresses < <(terraform state list | grep 'google_service_networking_connection' || true)

  local address network_name delete_error
  for address in "${connection_addresses[@]}"; do
    network_name="$(
      terraform state show -no-color "${address}" \
        | awk -F'= ' '
            /^[[:space:]]*network[[:space:]]*=/ {
              gsub(/"/, "", $2)
              n=split($2, parts, "/")
              print parts[n]
              exit
            }
          '
    )"

    if [[ -n "${network_name}" ]]; then
      echo "Deleting private service connection for network ${network_name}..."
      if ! delete_error="$(
        gcloud services vpc-peerings delete \
          --network="${network_name}" \
          --service=servicenetworking.googleapis.com \
          --quiet 2>&1 >/dev/null
      )"; then
        if grep -Eqi 'NOT_FOUND|not found|does not exist|There are no private service connections' <<<"${delete_error}"; then
          echo "Private service connection for ${network_name} is already absent; pruning state."
        else
          echo "${delete_error}" >&2
          return 1
        fi
      fi
    fi

    remove_state_if_present "${address}"
  done

  local global_address_entries=()
  mapfile -t global_address_entries < <(terraform state list | grep 'google_compute_global_address' || true)
  local reserved_name describe_error
  for address in "${global_address_entries[@]}"; do
    reserved_name="$(
      terraform state show -no-color "${address}" \
        | awk -F'= ' '
            /^[[:space:]]*name[[:space:]]*=/ { gsub(/"/, "", $2); print $2; exit }
          '
    )"

    if [[ -z "${reserved_name}" ]]; then
      continue
    fi

    if ! describe_error="$(
      gcloud compute addresses describe "${reserved_name}" \
        --global 2>&1 >/dev/null
    )"; then
      if grep -Eqi 'was not found|Could not fetch resource|NOT_FOUND' <<<"${describe_error}"; then
        echo "Reserved peering range ${reserved_name} is already absent; pruning state."
        remove_state_if_present "${address}"
        continue
      fi
      echo "${describe_error}" >&2
      return 1
    fi

    echo "Deleting reserved peering range ${reserved_name}..."
    gcloud compute addresses delete "${reserved_name}" \
      --global \
      --quiet >/dev/null
    remove_state_if_present "${address}"
  done
}

build_destroy_command() {
  local target_cloud="$1"
  shift

  local cmd=(terraform destroy)
  if [[ "${target_cloud}" != "all" ]]; then
    case "${target_cloud}" in
      gcp)
        cmd+=(
          -target=module.gcp_nat_route
          -target=module.gcp_instances
          -target=module.gcp_firewall
          -target=module.gcp_database
          -target=module.gcp_secrets
          -target=module.gcp_network
        )
        ;;
      aws)
        cmd+=(
          -target=module.aws_nat_route
          -target=module.aws_instances
          -target=module.aws_security_groups
          -target=module.aws_database
          -target=module.aws_secrets
          -target=module.aws_network
        )
        ;;
      azure)
        cmd+=(
          -target=module.azure_nat_route
          -target=module.azure_instances
          -target=module.azure_security_groups
          -target=module.azure_database
          -target=module.azure_secrets
          -target=module.azure_network
        )
        ;;
    esac
  fi

  cmd+=("$@")
  printf '%s\n' "${cmd[@]}"
}

if [[ "${TARGET_CLOUD}" == "all" || "${TARGET_CLOUD}" == "aws" ]]; then
  disable_aws_rds_deletion_protection
  force_delete_aws_secrets
fi

if [[ "${TARGET_CLOUD}" == "all" || "${TARGET_CLOUD}" == "gcp" ]]; then
  disable_gcp_sql_deletion_protection
  delete_gcp_sql_instances
  delete_gcp_private_service_access
fi

mapfile -t destroy_cmd < <(build_destroy_command "${TARGET_CLOUD}" "$@")
"${destroy_cmd[@]}"
