#!/bin/bash
set -euo pipefail

if [[ "${1:-}" != "--yes-really-destroy-stateful" ]]; then
  cat <<'EOF'
Usage:
  bash full-destroy.sh --yes-really-destroy-stateful [terraform destroy args...]

This script performs a deliberate full teardown of compute and protected
stateful resources across all enabled clouds by:
  1. copying the Terraform root into a temporary directory
  2. removing GCP/AWS hard destroy protections in the temporary copy only
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
import pathlib
import re
import sys

terraform_dir = pathlib.Path(sys.argv[1])

files = [
    terraform_dir / "modules" / "cloud" / "gcp" / "database" / "main.tf",
    terraform_dir / "modules" / "cloud" / "gcp" / "secrets" / "main.tf",
    terraform_dir / "modules" / "cloud" / "aws" / "database" / "main.tf",
    terraform_dir / "modules" / "cloud" / "aws" / "secrets" / "main.tf",
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

GCP and AWS protected resources are unguarded only inside this temporary copy.
AWS RDS final snapshots are disabled in the temporary copy to keep repeated lab
teardowns deterministic.
Running terraform destroy against the existing backend state now...
EOF

cd "${TMP_TERRAFORM_DIR}"
terraform init
terraform destroy "$@"
