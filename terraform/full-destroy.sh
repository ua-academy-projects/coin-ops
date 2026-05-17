#!/bin/bash
set -euo pipefail

if [[ "${1:-}" != "--yes-really-destroy-stateful" ]]; then
  cat <<'EOF'
Usage:
  bash full-destroy.sh --yes-really-destroy-stateful [terraform destroy args...]

This script performs a deliberate full teardown of compute and protected
stateful resources across all enabled clouds by:
  1. copying the Terraform root into a temporary directory
  2. removing GCP/AWS/Azure hard destroy protections in the temporary copy only
  3. running terraform destroy there against the same backend state

The checked-in Terraform files remain unchanged.
EOF
  exit 1
fi

shift

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

python3 - <<'PY' "${TMP_TERRAFORM_DIR}"
import json
import pathlib
import re
import shutil
import sys

terraform_dir = pathlib.Path(sys.argv[1])

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

files = [
    terraform_dir / "modules" / "cloud" / "gcp" / "database" / "main.tf",
    terraform_dir / "modules" / "cloud" / "gcp" / "secrets" / "main.tf",
    terraform_dir / "modules" / "cloud" / "aws" / "database" / "main.tf",
    terraform_dir / "modules" / "cloud" / "aws" / "secrets" / "main.tf",
    terraform_dir / "modules" / "cloud" / "azure" / "database" / "main.tf",
    terraform_dir / "modules" / "cloud" / "azure" / "secrets" / "main.tf",
]

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

GCP, AWS, and Azure protected resources are unguarded only inside this temporary copy.
AWS RDS final snapshots are disabled in the temporary copy to keep repeated lab
teardowns deterministic.
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
    aws rds modify-db-instance \
      --db-instance-identifier "${identifier}" \
      --no-deletion-protection \
      --apply-immediately >/dev/null

    aws rds wait db-instance-available \
      --db-instance-identifier "${identifier}"
  done
}

disable_aws_rds_deletion_protection
terraform destroy "$@"
