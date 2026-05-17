#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_PATH="${SCRIPT_DIR}/config/clouds.json"
BACKEND_PATH="${SCRIPT_DIR}/backend.active.tf"

if [[ ! -f "${BACKEND_PATH}" ]]; then
  cat >&2 <<EOF
Missing terraform/backend.active.tf.
Run the bootstrap for the selected control plane first, then run terraform init -reconfigure.
EOF
  exit 1
fi

control_plane="$(
  python3 - <<'PY' "${CONFIG_PATH}"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)

print(data.get("clouds", {}).get("control_plane", "gcp"))
PY
)"

case "${control_plane}" in
  gcp) expected_backend="gcs" ;;
  aws) expected_backend="s3" ;;
  azure) expected_backend="azurerm" ;;
  *)
    echo "Unsupported clouds.control_plane '${control_plane}' in ${CONFIG_PATH}" >&2
    exit 1
    ;;
esac

if ! grep -q "backend \"${expected_backend}\"" "${BACKEND_PATH}"; then
  actual_backend="$(
    sed -n 's/.*backend "\([^"]*\)".*/\1/p' "${BACKEND_PATH}" | head -n 1
  )"

  cat >&2 <<EOF
Terraform backend mismatch.

clouds.control_plane: ${control_plane}
expected backend:     ${expected_backend}
active backend:       ${actual_backend:-unknown}

backend.active.tf is generated and is the real Terraform backend selector.
Regenerate it with the matching bootstrap script, then reconfigure Terraform:

  cd ${SCRIPT_DIR}
  bash bootstrap-${control_plane}.sh
  terraform init -reconfigure

Do not use -migrate-state unless you intentionally want to copy state between
backends.
EOF
  exit 1
fi

echo "Terraform backend matches clouds.control_plane (${control_plane} -> ${expected_backend})."
