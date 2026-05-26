#!/usr/bin/env bash
# =============================================================================
# deploy/k3s/setup.sh
# =============================================================================
# One-shot script to deploy the Coin Ops application stack onto your cloud 
# K3s cluster using an Ansible multi-namespace zero-trust architecture.
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
[[ -f "${ENV_FILE}" ]] || err ".env not found at ${ENV_FILE}. Sourced credentials required."
# shellcheck disable=SC2046
export $(grep -v '^#' "${ENV_FILE}" | grep -v '^$' | xargs)

# ── 2. Kubectl Connection Check ───────────────────────────────────────────────
info "Verifying cloud cluster API connectivity..."
export KUBECONFIG="${PROJECT_ROOT}/terraform/k3s/.kube/config"

if ! kubectl cluster-info &>/dev/null; then
  err "Cannot reach cloud K3s cluster. Ensure your Terraform infrastructure is active and your VPN/SSH tunnel is running."
fi
success "kubectl successfully connected to: $(kubectl config current-context)"

# ── 3. Delegate to deploy.sh ──────────────────────────────────────────────────
info "Starting deployment..."
"${SCRIPT_DIR}/deploy.sh"

# ── 4. Headlamp Bearer Token Generation ───────────────────────────────────────
info "Generating Headlamp bearer token for cluster dashboard..."
HEADLAMP_TOKEN=$(kubectl create token headlamp \
  --namespace headlamp \
  --duration=8760h 2>/dev/null || \
  kubectl get secret \
    "$(kubectl get serviceaccount headlamp -n headlamp \
       -o jsonpath='{.secrets[0].name}')" \
    -n headlamp \
    -o jsonpath='{.data.token}' | base64 --decode)

# ── 5. Print Deployment Summary ──────────────────────────────────────────────
APP_DOMAIN="${APP_DOMAIN:-coinops.test}"

echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅  Cloud K3s environment setup complete!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}Application Endpoint${NC}"
echo -e "  ─────────────────────────────────────────────────────"
echo -e "  Frontend UI  →  https://${APP_DOMAIN}/"
echo -e "  Backend API  →  https://${APP_DOMAIN}/api/"
echo ""
echo -e "  ${CYAN}Headlamp Dashboard (Cluster Admin)${NC}"
echo -e "  ─────────────────────────────────────────────────────"
echo -e "  1. Establish port-forwarding connection:"
echo -e "     ${YELLOW}kubectl -n headlamp port-forward svc/headlamp 4466:80 &${NC}"
echo -e "  2. Access locally:"
echo -e "     ${YELLOW}http://localhost:4466/${NC}"
echo -e "  3. Paste this Bearer Token to authenticate:"
echo ""
echo -e "${YELLOW}${HEADLAMP_TOKEN}${NC}"
echo ""
echo -e "  ${CYAN}Useful Diagnostics${NC}"
echo -e "  ─────────────────────────────────────────────────────"
echo -e "  kubectl get pods -n coin-ops-app"
echo -e "  kubectl get pods -n coin-ops-infra"
echo -e "  kubectl get ingress -n coin-ops-app"
echo ""
