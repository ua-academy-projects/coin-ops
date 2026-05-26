#!/usr/bin/env bash
# =============================================================================
# deploy/k3s/deploy.sh
# =============================================================================
# Thin wrapper that loads environment configurations and executes the cloud 
# K3s deployment pipeline using Ansible.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[ERR]${NC}   $*"; exit 1; }

# ── 1. Load .env ─────────────────────────────────────────────────────────────
[[ -f "${ENV_FILE}" ]] || err ".env not found at ${ENV_FILE}. Run setup.sh or create .env first."
info "Loading .env configuration..."
# shellcheck disable=SC2046
export $(grep -v '^#' "${ENV_FILE}" | grep -v '^$' | xargs)

# ── 2. Verify Ansible and dependencies ─────────────────────────────────────────
info "Verifying Ansible requirements..."
if ! command -v ansible-playbook &>/dev/null; then
  err "ansible-playbook is not installed. Install it first: brew install ansible"
fi

# Check Python kubernetes client dependency
if ! python3 -c "import kubernetes, yaml" &>/dev/null; then
  warn "Python 'kubernetes' and 'PyYAML' libraries are missing. Attempting installation..."
  pip3 install --user kubernetes PyYAML || err "Failed to install required Python libraries. Run: pip3 install kubernetes PyYAML"
fi

# Ensure kubernetes.core collection is present
if ! ansible-galaxy collection list | grep -q "kubernetes.core" &>/dev/null; then
  info "Installing kubernetes.core Ansible collection..."
  ansible-galaxy collection install kubernetes.core || err "Failed to install kubernetes.core collection."
fi

# ── 3. Run Playbook ───────────────────────────────────────────────────────────
info "Orchestrating Cloud K3s deployment via Ansible..."
cd "${PROJECT_ROOT}/ansible"
ansible-playbook \
  -i localhost, \
  "playbooks/deploy-k3s.yml"

success "Workloads deployed to cloud cluster successfully!"
