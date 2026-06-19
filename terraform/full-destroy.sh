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
  4. pre-cleaning Terraform-managed Cloudflare Tunnel / Access / DNS resources when applicable
  5. running terraform destroy there against the same backend state

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

def remove_hcl_block(content, start):
    line_start = content.rfind("\n", 0, start) + 1
    open_brace = content.find("{", start)
    if open_brace == -1:
        return content
    depth = 0
    in_string = False
    escape = False
    for pos in range(open_brace, len(content)):
        char = content[pos]
        if in_string:
            if escape:
                escape = False
            elif char == "\\":
                escape = True
            elif char == '"':
                in_string = False
            continue
        if char == '"':
            in_string = True
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                line_end = content.find("\n", pos)
                line_end = len(content) if line_end == -1 else line_end + 1
                return content[:line_start] + content[line_end:]
    return content

def remove_required_provider(content, provider_name):
    match = re.search(rf"(?m)^\s*{re.escape(provider_name)}\s*=\s*\{{", content)
    return remove_hcl_block(content, match.start()) if match else content

def remove_provider_block(content, provider_name):
    match = re.search(rf'(?m)^provider\s+"{re.escape(provider_name)}"\s*\{{', content)
    return remove_hcl_block(content, match.start()) if match else content

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
    providers = remove_required_provider(providers, "azurerm")
    providers = remove_provider_block(providers, "azurerm")
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
    if name == "gcp":
        files.append(terraform_dir / "gcp_cnpg_backup.tf")
    if name == "aws":
        files.append(terraform_dir / "aws_cnpg_backup.tf")

lifecycle_pattern = re.compile(
    r"\n\s*lifecycle\s*\{\s*\n\s*prevent_destroy\s*=\s*true\s*\n\s*\}\s*\n",
    re.MULTILINE,
)

for path in files:
    if not path.exists():
        continue
    content = path.read_text(encoding="utf-8")
    content = lifecycle_pattern.sub("\n", content)
    if path.name in ("gcp_cnpg_backup.tf", "aws_cnpg_backup.tf"):
        content = re.sub(
            r"(?m)^(\s*)count\s*=\s*local\.(?:gcp_|aws_)?cnpg_backup_enabled\s*\?\s*1\s*:\s*0\s*$",
            r"\1count = 1",
            content,
        )
    if path.name == "gcp_cnpg_backup.tf":
        if re.search(r"(?m)^\s*force_destroy\s*=", content):
            content = re.sub(
                r"(?m)^(\s*)force_destroy\s*=.*$",
                r"\1force_destroy = true",
                content,
                count=1,
            )
        else:
            content = re.sub(
                r'(?m)^(\s*public_access_prevention\s*=\s*"enforced"\s*)$',
                r"\1\n  force_destroy               = true",
                content,
                count=1,
            )
    if path.name == "aws_cnpg_backup.tf":
        content = re.sub(
            r"(?m)^(\s*)force_destroy\s*=.*$",
            r"\1force_destroy = true",
            content,
            count=1,
        )
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

GCP_PROJECT_ARG=()
if command -v gcloud >/dev/null 2>&1; then
  CURRENT_GCP_PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
  if [[ -n "${CURRENT_GCP_PROJECT}" && "${CURRENT_GCP_PROJECT}" != "(unset)" ]]; then
    GCP_PROJECT_ARG=(--project="${CURRENT_GCP_PROJECT}")
  fi
fi

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

empty_aws_s3_bucket() {
  local bucket="$1"

  if [[ -z "${bucket}" ]]; then
    return 0
  fi

  echo "Emptying versioned S3 bucket ${bucket} before Terraform destroys it..."

  local uploads_file upload_entries_file upload_error
  uploads_file="$(mktemp "${TMP_ROOT}/s3-uploads.XXXXXX.json")"
  upload_entries_file="$(mktemp "${TMP_ROOT}/s3-upload-entries.XXXXXX.tsv")"
  if ! upload_error="$(aws s3api list-multipart-uploads --bucket "${bucket}" --output json 2>&1 >"${uploads_file}")"; then
    if grep -Eqi 'NoSuchBucket|Not Found|404' <<<"${upload_error}"; then
      echo "S3 bucket ${bucket} is already absent."
      return 0
    fi

    echo "Failed to list multipart uploads for S3 bucket ${bucket}:" >&2
    echo "${upload_error}" >&2
    return 1
  fi

  python3 - <<'PY' "${uploads_file}" >"${upload_entries_file}"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

for upload in data.get("Uploads", []) or []:
    key = upload.get("Key", "")
    upload_id = upload.get("UploadId", "")
    if key and upload_id:
        print(f"{key}\t{upload_id}")
PY

  local key upload_id
  local abort_error
  while IFS=$'\t' read -r key upload_id; do
    [[ -n "${key}" && -n "${upload_id}" ]] || continue
    if ! abort_error="$(aws s3api abort-multipart-upload \
      --bucket "${bucket}" \
      --key "${key}" \
      --upload-id "${upload_id}" 2>&1 >/dev/null)"; then
      echo "Failed to abort multipart upload for s3://${bucket}/${key}:" >&2
      echo "${abort_error}" >&2
      return 1
    fi
  done <"${upload_entries_file}"

  local rm_error=""
  if ! rm_error="$(aws s3 rm "s3://${bucket}" --recursive 2>&1 >/dev/null)"; then
    if grep -Eqi 'NoSuchBucket|Not Found|404' <<<"${rm_error}"; then
      echo "S3 bucket ${bucket} is already absent."
      return 0
    fi

    echo "Failed to remove current objects from S3 bucket ${bucket}:" >&2
    echo "${rm_error}" >&2
    return 1
  fi

  local versions_file delete_file count list_error
  while true; do
    versions_file="$(mktemp "${TMP_ROOT}/s3-versions.XXXXXX.json")"
    delete_file="$(mktemp "${TMP_ROOT}/s3-delete.XXXXXX.json")"

    if ! list_error="$(aws s3api list-object-versions --bucket "${bucket}" --output json 2>&1 >"${versions_file}")"; then
      if grep -Eqi 'NoSuchBucket|Not Found|404' <<<"${list_error}"; then
        echo "S3 bucket ${bucket} is already absent."
        return 0
      fi

      echo "Failed to list object versions for S3 bucket ${bucket}:" >&2
      echo "${list_error}" >&2
      return 1
    fi

    count="$(
      python3 - <<'PY' "${versions_file}" "${delete_file}"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

objects = []
for item in (data.get("Versions", []) or []) + (data.get("DeleteMarkers", []) or []):
    key = item.get("Key")
    version_id = item.get("VersionId")
    if key and version_id:
        objects.append({"Key": key, "VersionId": version_id})

objects = objects[:1000]
with open(sys.argv[2], "w", encoding="utf-8") as handle:
    json.dump({"Objects": objects, "Quiet": True}, handle)

print(len(objects))
PY
    )"

    if [[ "${count}" -eq 0 ]]; then
      echo "S3 bucket ${bucket} is empty."
      return 0
    fi

    echo "Deleting ${count} object version(s) from ${bucket}..."
    local delete_error
    if ! delete_error="$(aws s3api delete-objects \
      --bucket "${bucket}" \
      --delete "file://${delete_file}" 2>&1 >/dev/null)"; then
      echo "Failed to delete object versions from S3 bucket ${bucket}:" >&2
      echo "${delete_error}" >&2
      return 1
    fi
  done
}

empty_aws_s3_buckets() {
  if ! command -v aws >/dev/null 2>&1; then
    return 0
  fi

  local bucket_candidates_file
  bucket_candidates_file="$(mktemp "${TMP_ROOT}/s3-bucket-candidates.XXXXXX.txt")"

  local addresses=()
  mapfile -t addresses < <(terraform state list | grep 'aws_s3_bucket\.cnpg_backups' || true)

  if [[ "${#addresses[@]}" -gt 0 ]]; then
    local address bucket
    for address in "${addresses[@]}"; do
      bucket="$(
        terraform state show -no-color "${address}" \
          | awk -F'= ' '
              /^[[:space:]]*bucket[[:space:]]*=/ { gsub(/"/, "", $2); print $2; found=1; exit }
              /^[[:space:]]*id[[:space:]]*=/ { fallback=$2 }
              END {
                if (!found && fallback != "") {
                  gsub(/"/, "", fallback)
                  print fallback
                }
              }
            '
      )"

      if [[ -z "${bucket}" ]]; then
        echo "Could not determine S3 bucket name for ${address}; skipping state-derived candidate."
        continue
      fi

      printf '%s\n' "${bucket}" >>"${bucket_candidates_file}"
    done
  fi

  python3 - <<'PY' "${TMP_TERRAFORM_DIR}/config" >>"${bucket_candidates_file}"
import json
import pathlib
import sys

config_dir = pathlib.Path(sys.argv[1])

for name in ("ansible-runtime.json", "hosts.json"):
    path = config_dir / name
    if not path.exists():
        continue

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        continue

    aws = data.get("aws", {})
    bucket = aws.get("cnpg_backup", {}).get("bucket", "")
    if bucket:
        print(bucket)
PY

  if [[ ! -s "${bucket_candidates_file}" ]]; then
    return 0
  fi

  local bucket
  while IFS= read -r bucket; do
    [[ -n "${bucket}" ]] || continue
    empty_aws_s3_bucket "${bucket}"
  done < <(sort -u "${bucket_candidates_file}")
}

aws_eks_cluster_name() {
  python3 - <<'PY' "${TMP_TERRAFORM_DIR}/config"
import json
import pathlib
import sys

config_dir = pathlib.Path(sys.argv[1])
general = json.loads((config_dir / "general.json").read_text(encoding="utf-8")).get("general", {})
deploy = json.loads((config_dir / "deploy.json").read_text(encoding="utf-8")).get("deploy", {})
print(deploy.get("eks", {}).get("cluster_name", f"{general.get('project_name', 'coin-ops')}-eks"))
PY
}

list_aws_eks_public_ingress_allocation_ids() {
  local addresses=()
  mapfile -t addresses < <(terraform state list | grep 'aws_eip\.aws_eks_public_ingress' || true)

  local address allocation_id
  for address in "${addresses[@]}"; do
    allocation_id="$(
      terraform state show -no-color "${address}" \
        | awk -F'= ' '
            /^[[:space:]]*allocation_id[[:space:]]*=/ { gsub(/"/, "", $2); print $2; found=1; exit }
            /^[[:space:]]*id[[:space:]]*=/ { fallback=$2 }
            END {
              if (!found && fallback != "") {
                gsub(/"/, "", fallback)
                print fallback
              }
            }
          '
    )"

    [[ -n "${allocation_id}" ]] && printf '%s\n' "${allocation_id}"
  done
}

wait_for_aws_eip_disassociated() {
  local allocation_id="$1"
  local attempts=60
  local describe_output

  for ((i = 1; i <= attempts; i++)); do
    if ! describe_output="$(
      aws ec2 describe-addresses \
        --allocation-ids "${allocation_id}" \
        --output json 2>/dev/null
    )"; then
      return 0
    fi

    if python3 - <<'PY' "${describe_output}"
import json
import sys

addresses = json.loads(sys.argv[1]).get("Addresses", [])
raise SystemExit(0 if not addresses or not addresses[0].get("AssociationId") else 1)
PY
    then
      return 0
    fi

    sleep 10
  done

  echo "Timed out waiting for EIP ${allocation_id} to become disassociated." >&2
  return 1
}

delete_aws_eks_load_balancers() {
  if ! command -v aws >/dev/null 2>&1; then
    return 0
  fi

  local cluster_name
  cluster_name="$(aws_eks_cluster_name)"
  if [[ -z "${cluster_name}" ]]; then
    return 0
  fi

  local load_balancers_file matching_lbs_file
  load_balancers_file="$(mktemp "${TMP_ROOT}/aws-elbv2-load-balancers.XXXXXX.json")"
  matching_lbs_file="$(mktemp "${TMP_ROOT}/aws-elbv2-matching-load-balancers.XXXXXX.txt")"

  if ! aws elbv2 describe-load-balancers --output json >"${load_balancers_file}" 2>/dev/null; then
    return 0
  fi

  python3 - <<'PY' "${load_balancers_file}" "${matching_lbs_file}" "${cluster_name}"
import json
import subprocess
import sys

load_balancers_path, output_path, cluster_name = sys.argv[1:]
cluster_tag_key = f"kubernetes.io/cluster/{cluster_name}"

with open(load_balancers_path, encoding="utf-8") as handle:
    load_balancers = json.load(handle).get("LoadBalancers", [])

arns = [lb.get("LoadBalancerArn", "") for lb in load_balancers if lb.get("LoadBalancerArn")]
matches = []
for i in range(0, len(arns), 20):
    chunk = arns[i:i + 20]
    if not chunk:
        continue
    result = subprocess.run(
        ["aws", "elbv2", "describe-tags", "--resource-arns", *chunk, "--output", "json"],
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        continue
    for description in json.loads(result.stdout).get("TagDescriptions", []):
        tags = {tag.get("Key"): tag.get("Value") for tag in description.get("Tags", [])}
        if tags.get(cluster_tag_key) == "owned":
            matches.append(description.get("ResourceArn"))

with open(output_path, "w", encoding="utf-8") as handle:
    for arn in matches:
        if arn:
            handle.write(f"{arn}\n")
PY

  local lb_arn
  if [[ -s "${matching_lbs_file}" ]]; then
    echo "Deleting Kubernetes-managed AWS load balancers for EKS cluster ${cluster_name}..."
    while IFS= read -r lb_arn; do
      [[ -n "${lb_arn}" ]] || continue
      echo "Deleting AWS load balancer ${lb_arn}..."
      aws elbv2 delete-load-balancer --load-balancer-arn "${lb_arn}" >/dev/null || true
    done <"${matching_lbs_file}"

    while IFS= read -r lb_arn; do
      [[ -n "${lb_arn}" ]] || continue
      aws elbv2 wait load-balancers-deleted --load-balancer-arns "${lb_arn}" || true
    done <"${matching_lbs_file}"
  fi

  local allocation_ids=()
  mapfile -t allocation_ids < <(list_aws_eks_public_ingress_allocation_ids | sort -u)
  local allocation_id
  for allocation_id in "${allocation_ids[@]}"; do
    [[ -n "${allocation_id}" ]] || continue
    echo "Waiting for Kubernetes-managed load balancer to release EIP ${allocation_id}..."
    wait_for_aws_eip_disassociated "${allocation_id}"
  done

  local target_groups_file matching_target_groups_file
  target_groups_file="$(mktemp "${TMP_ROOT}/aws-elbv2-target-groups.XXXXXX.json")"
  matching_target_groups_file="$(mktemp "${TMP_ROOT}/aws-elbv2-matching-target-groups.XXXXXX.txt")"

  if ! aws elbv2 describe-target-groups --output json >"${target_groups_file}" 2>/dev/null; then
    return 0
  fi

  python3 - <<'PY' "${target_groups_file}" "${matching_target_groups_file}" "${cluster_name}"
import json
import subprocess
import sys

target_groups_path, output_path, cluster_name = sys.argv[1:]
cluster_tag_key = f"kubernetes.io/cluster/{cluster_name}"

with open(target_groups_path, encoding="utf-8") as handle:
    target_groups = json.load(handle).get("TargetGroups", [])

arns = [group.get("TargetGroupArn", "") for group in target_groups if group.get("TargetGroupArn")]
matches = []
for i in range(0, len(arns), 20):
    chunk = arns[i:i + 20]
    if not chunk:
        continue
    result = subprocess.run(
        ["aws", "elbv2", "describe-tags", "--resource-arns", *chunk, "--output", "json"],
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        continue
    for description in json.loads(result.stdout).get("TagDescriptions", []):
        tags = {tag.get("Key"): tag.get("Value") for tag in description.get("Tags", [])}
        if tags.get(cluster_tag_key) == "owned":
            matches.append(description.get("ResourceArn"))

with open(output_path, "w", encoding="utf-8") as handle:
    for arn in matches:
        if arn:
            handle.write(f"{arn}\n")
PY

  if [[ -s "${matching_target_groups_file}" ]]; then
    echo "Deleting Kubernetes-managed AWS target groups for EKS cluster ${cluster_name}..."
    local target_group_arn
    while IFS= read -r target_group_arn; do
      [[ -n "${target_group_arn}" ]] || continue
      echo "Deleting AWS target group ${target_group_arn}..."
      aws elbv2 delete-target-group --target-group-arn "${target_group_arn}" >/dev/null || true
    done <"${matching_target_groups_file}"
  fi
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
      "${GCP_PROJECT_ARG[@]}" \
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

gcp_private_service_connection_exists() {
  local network_name="$1"
  local peerings_output=""

    if ! peerings_output="$(
    gcloud services vpc-peerings list \
      "${GCP_PROJECT_ARG[@]}" \
      --network="${network_name}" \
      --service=servicenetworking.googleapis.com \
      --format='value(network)' 2>/dev/null
  )"; then
    return 1
  fi

  [[ -n "${peerings_output}" ]]
}

list_gcp_network_peerings() {
  local network_name="$1"

  gcloud compute networks peerings list \
    "${GCP_PROJECT_ARG[@]}" \
    --network="${network_name}" \
    --format='value(name)' 2>/dev/null || true
}

gcp_compute_peerings_exist() {
  local network_name="$1"
  local peerings_output=""

  peerings_output="$(list_gcp_network_peerings "${network_name}")"
  [[ -n "${peerings_output}" ]]
}

force_delete_gcp_compute_peerings() {
  local network_name="$1"
  local peering_names=()
  local peering_name

  mapfile -t peering_names < <(list_gcp_network_peerings "${network_name}")

  if [[ "${#peering_names[@]}" -eq 0 ]]; then
    return 0
  fi

  echo "Attempting break-glass delete of all Compute Engine peerings for ${network_name}..."

  for peering_name in "${peering_names[@]}"; do
    [[ -n "${peering_name}" ]] || continue
    echo "  Trying compute peering delete: ${peering_name}"

    if gcloud compute networks peerings delete "${peering_name}" \
      "${GCP_PROJECT_ARG[@]}" \
      --network="${network_name}" \
      --quiet >/dev/null 2>&1; then
      echo "  Compute peering delete succeeded: ${peering_name}"
      continue
    fi

    echo "  Compute peering delete did not complete cleanly, requesting delete: ${peering_name}"
    gcloud compute networks peerings request-delete "${peering_name}" \
      "${GCP_PROJECT_ARG[@]}" \
      --network="${network_name}" \
      --quiet >/dev/null 2>&1 || true
  done
}

delete_gcp_private_service_connection_with_retry() {
  local network_name="$1"
  local attempts=3
  local sleep_seconds=10
  local delete_error=""

  if ! gcp_private_service_connection_exists "${network_name}"; then
    echo "Private service connection for ${network_name} is already absent."
    return 0
  fi

  if gcp_compute_peerings_exist "${network_name}"; then
    echo "Private service connection for ${network_name} still has underlying Compute peerings. Deleting them first..."
    force_delete_gcp_compute_peerings "${network_name}"
    if ! gcp_private_service_connection_exists "${network_name}"; then
      echo "Private service connection for ${network_name} disappeared after direct Compute peering delete."
      return 0
    fi
    if ! gcp_compute_peerings_exist "${network_name}"; then
      echo "Underlying Compute peerings for ${network_name} are gone after direct delete; proceeding without waiting for Service Networking to converge."
      return 0
    fi
  fi

  for ((i = 1; i <= attempts; i++)); do
    if ! gcp_private_service_connection_exists "${network_name}"; then
      echo "Private service connection for ${network_name} is already absent."
      return 0
    fi

    if delete_error="$(
      gcloud services vpc-peerings delete \
        "${GCP_PROJECT_ARG[@]}" \
        --network="${network_name}" \
        --service=servicenetworking.googleapis.com \
        --quiet 2>&1 >/dev/null
    )"; then
      return 0
    fi

    if grep -Eqi 'NOT_FOUND|not found|does not exist|There are no private service connections' <<<"${delete_error}"; then
      return 0
    fi

    if grep -Eqi 'Producer services .* are still using this connection|FLOW_SN_DC_RESOURCE_PREVENTING_DELETE_CONNECTION|PreconditionFailure' <<<"${delete_error}"; then
      if ! gcp_private_service_connection_exists "${network_name}"; then
        echo "Private service connection for ${network_name} disappeared while GCP was still reporting producer cleanup."
        return 0
      fi

      if gcp_compute_peerings_exist "${network_name}"; then
        force_delete_gcp_compute_peerings "${network_name}"
        if ! gcp_private_service_connection_exists "${network_name}"; then
          echo "Private service connection for ${network_name} disappeared after break-glass Compute peering delete."
          return 0
        fi
        if ! gcp_compute_peerings_exist "${network_name}"; then
          echo "Underlying Compute peerings for ${network_name} are gone after break-glass delete; proceeding without waiting for Service Networking to converge."
          return 0
        fi
      fi

      echo "Private service connection for ${network_name} is still in use by a producer service. Waiting for GCP cleanup (${i}/${attempts})..."
      sleep "${sleep_seconds}"
      continue
    fi

    echo "${delete_error}" >&2
    return 1
  done

  echo "Timed out waiting for private service connection on ${network_name} to become deletable." >&2
  if ! gcp_compute_peerings_exist "${network_name}"; then
    echo "Underlying Compute peerings for ${network_name} are already absent; proceeding despite stale Service Networking delete errors." >&2
    return 0
  fi
  echo "${delete_error}" >&2
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

    if gcloud sql instances describe "${instance_name}" "${GCP_PROJECT_ARG[@]}" >/dev/null 2>&1; then
      echo "Deleting Cloud SQL instance ${instance_name}..."
      gcloud sql instances patch "${instance_name}" \
        "${GCP_PROJECT_ARG[@]}" \
        --no-deletion-protection \
        --quiet >/dev/null
      gcloud sql instances delete "${instance_name}" \
        "${GCP_PROJECT_ARG[@]}" \
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

  local address network_name
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
      delete_gcp_private_service_connection_with_retry "${network_name}"
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
        "${GCP_PROJECT_ARG[@]}" \
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
      "${GCP_PROJECT_ARG[@]}" \
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
          -target=random_bytes.headlamp_tunnel_secret
          -target=cloudflare_zero_trust_tunnel_cloudflared_config.headlamp
          -target=cloudflare_zero_trust_tunnel_cloudflared.headlamp
          -target=cloudflare_zero_trust_access_policy.headlamp
          -target=cloudflare_zero_trust_access_application.headlamp
          -target=cloudflare_zero_trust_access_identity_provider.github
          -target=module.cloudflare_dns_records
          -target=module.gcp_nat_route
          -target=module.gcp_instances
          -target=module.gcp_firewall
          -target=module.gcp_database
          -target=module.gcp_secrets
          -target=google_storage_bucket_iam_member.cnpg_backup_object_admin
          -target=google_storage_bucket_iam_member.cnpg_backup_bucket_reader
          -target=google_service_account_key.cnpg_backup
          -target=google_service_account.cnpg_backup
          -target=google_storage_bucket.cnpg_backups
          -target=module.gcp_network
        )
        ;;
      aws)
        cmd+=(
          -target=module.aws_nat_route
          -target=module.aws_k3s_api_lb
          -target=module.aws_k3s_public_ingress_lb
          -target=module.aws_observability_monitoring
          -target=module.aws_observability_logs
          -target=module.aws_instances
          -target=module.aws_observability_iam
          -target=module.aws_security_groups
          -target=module.aws_database
          -target=module.aws_secrets
          -target=aws_iam_access_key.cnpg_backup
          -target=aws_iam_user_policy.cnpg_backup
          -target=aws_iam_user.cnpg_backup
          -target=aws_s3_bucket_server_side_encryption_configuration.cnpg_backups
          -target=aws_s3_bucket_versioning.cnpg_backups
          -target=aws_s3_bucket_public_access_block.cnpg_backups
          -target=aws_s3_bucket.cnpg_backups
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
  delete_aws_eks_load_balancers
  disable_aws_rds_deletion_protection
  force_delete_aws_secrets
  empty_aws_s3_buckets
fi

if [[ "${TARGET_CLOUD}" == "all" || "${TARGET_CLOUD}" == "gcp" ]]; then
  bash "${TMP_TERRAFORM_DIR}/cloudflare-cleanup.sh" --prune-state
  disable_gcp_sql_deletion_protection
  delete_gcp_sql_instances
  delete_gcp_private_service_access
fi

mapfile -t destroy_cmd < <(build_destroy_command "${TARGET_CLOUD}" "$@")
"${destroy_cmd[@]}"
