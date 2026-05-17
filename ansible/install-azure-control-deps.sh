#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_DIR="${REPO_ROOT}/.venv"
GENERATED_ENV="${REPO_ROOT}/local/generated-azure-python-env.sh"

COLLECTION_PATH="$(
python3 - <<'PY'
from pathlib import Path

candidates = [
    Path.home() / ".ansible" / "collections" / "ansible_collections" / "azure" / "azcollection",
    Path("/usr/share/ansible/collections/ansible_collections/azure/azcollection"),
    Path("/usr/lib/python3/dist-packages/ansible_collections/azure/azcollection"),
]

for path in candidates:
    if (path / "requirements.txt").exists():
        print(path)
        break
else:
    raise SystemExit("Could not locate azure.azcollection on this host.")
PY
)"

REQ_FILE="${COLLECTION_PATH}/requirements.txt"

echo "Creating repo-local virtualenv at ${VENV_DIR}"
python3 -m venv --system-site-packages "${VENV_DIR}"

echo "Installing Azure control-host Python dependencies from ${REQ_FILE}"
"${VENV_DIR}/bin/python" -m pip install --upgrade pip
"${VENV_DIR}/bin/python" -m pip install -r "${REQ_FILE}"

SITE_PACKAGES="$("${VENV_DIR}/bin/python" - <<'PY'
import sysconfig
print(sysconfig.get_path("purelib"))
PY
)"

mkdir -p "${REPO_ROOT}/local"
cat > "${GENERATED_ENV}" <<EOF
#!/bin/bash
export PATH="${VENV_DIR}/bin:\${PATH}"
export PYTHONPATH="${SITE_PACKAGES}\${PYTHONPATH:+:\${PYTHONPATH}}"
EOF
chmod 600 "${GENERATED_ENV}"

cat <<EOF
Azure Ansible control-host dependencies installed.

Generated helper env:
  ${GENERATED_ENV}

If you already source local/generated-azure-env.sh, it will pick this up automatically.
Otherwise source it manually:
  source ${GENERATED_ENV}
EOF
