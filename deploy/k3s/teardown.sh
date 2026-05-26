#!/usr/bin/env bash
# =============================================================================
# deploy/k3s/teardown.sh
# =============================================================================
# Cleanly deletes the application, infrastructure, and routing namespaces
# from your cloud K3s cluster, freeing up all cluster resources.
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
[[ -f "${ENV_FILE}" ]] || err ".env not found at ${ENV_FILE}. Configuration required."
# shellcheck disable=SC2046
export $(grep -v '^#' "${ENV_FILE}" | grep -v '^$' | xargs)

PREFIX="${PREFIX:-coin-ops}"
APP_NAMESPACE="${PREFIX}-app"
INFRA_NAMESPACE="${PREFIX}-infra"
INGRESS_NAMESPACE="${PREFIX}-ingress"

# ── 2. Kubectl Connection Check ───────────────────────────────────────────────
info "Verifying cloud cluster API connectivity..."
export KUBECONFIG="${PROJECT_ROOT}/terraform/k3s/.kube/config"

if ! kubectl cluster-info &>/dev/null; then
  err "Cannot reach cloud K3s cluster. Check VPN/SSH tunnel or active connection."
fi
success "kubectl connected."

# ── 3. Clean Resources ────────────────────────────────────────────────────────
info "Decomissioning namespaces: ${APP_NAMESPACE}, ${INFRA_NAMESPACE}, ${INGRESS_NAMESPACE}..."
kubectl delete namespace \
  "${APP_NAMESPACE}" \
  "${INFRA_NAMESPACE}" \
  "${INGRESS_NAMESPACE}" \
  --ignore-not-found

success "Clean teardown complete. All deployed workloads removed."
