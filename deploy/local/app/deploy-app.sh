#!/usr/bin/env bash
# =============================================================================
# deploy/local/app/deploy-app.sh
# =============================================================================
# Deploys the real Coin Ops application into the running k3d cluster.
#
# Prerequisites:
#   • k3d cluster coin-ops-local must be running (run ../setup.sh first)
#   • GHCR credentials must be available (read from .env in project root)
#
# Usage:
#   ./deploy/local/app/deploy-app.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }

# ── Load .env ─────────────────────────────────────────────────────────────────
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "ERROR: .env not found at ${ENV_FILE}"
  exit 1
fi
# shellcheck disable=SC2046
export $(grep -v '^#' "${ENV_FILE}" | grep -v '^$' | xargs)

# ── Configure KUBECONFIG for k3s ──────────────────────────────────────────────
export KUBECONFIG="${PROJECT_ROOT}/terraform/k3s/.kube/config"
CURRENT_CTX=$(kubectl config current-context 2>/dev/null || echo "none")
success "Context: ${CURRENT_CTX}"

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — Create GHCR image pull secret
# ─────────────────────────────────────────────────────────────────────────────
info "Creating GHCR image pull secret..."
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username="${GHCR_USERNAME}" \
  --docker-password="${GHCR_TOKEN}" \
  --namespace=coin-ops \
  --dry-run=client -o yaml | kubectl apply -f -
success "ghcr-secret created/updated."

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — Remove placeholder deployments (nginx/http-echo)
# ─────────────────────────────────────────────────────────────────────────────
info "Removing placeholder services..."
kubectl delete deployment frontend backend --namespace=coin-ops --ignore-not-found
kubectl delete service frontend backend --namespace=coin-ops --ignore-not-found
kubectl delete configmap frontend-html --namespace=coin-ops --ignore-not-found
kubectl delete ingress coin-ops-local --namespace=coin-ops --ignore-not-found
# kubectl delete middleware strip-api-prefix --namespace=coin-ops --ignore-not-found
success "Placeholders removed."

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — Deploy secrets
# ─────────────────────────────────────────────────────────────────────────────
info "Applying secrets..."
kubectl apply -f "${SCRIPT_DIR}/secrets.yaml"
success "Secrets applied."

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — Deploy infrastructure (Postgres, RabbitMQ, Redis)
# ─────────────────────────────────────────────────────────────────────────────
info "Deploying infrastructure (Postgres, RabbitMQ, Redis)..."
kubectl apply -f "${SCRIPT_DIR}/postgres.yaml"
kubectl apply -f "${SCRIPT_DIR}/infra.yaml"

info "Waiting for Postgres to be ready..."
kubectl wait --for=condition=ready pod \
  --selector=app=postgres --namespace=coin-ops --timeout=120s

info "Waiting for RabbitMQ to be ready..."
kubectl wait --for=condition=ready pod \
  --selector=app=rabbitmq --namespace=coin-ops --timeout=120s

info "Waiting for Redis to be ready..."
kubectl wait --for=condition=ready pod \
  --selector=app=redis --namespace=coin-ops --timeout=60s

success "Infrastructure ready."

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5 — Deploy application services
# ─────────────────────────────────────────────────────────────────────────────
info "Deploying application services (proxy, history-api, history-consumer, ui)..."
envsubst < "${SCRIPT_DIR}/proxy.yaml" | kubectl apply -f -
envsubst < "${SCRIPT_DIR}/history.yaml" | kubectl apply -f -
envsubst < "${SCRIPT_DIR}/ui.yaml" | kubectl apply -f -

info "Waiting for proxy..."
kubectl wait --for=condition=ready pod \
  --selector=app=proxy --namespace=coin-ops --timeout=120s

info "Waiting for history-api..."
kubectl wait --for=condition=ready pod \
  --selector=app=history-api --namespace=coin-ops --timeout=120s

info "Waiting for ui..."
kubectl wait --for=condition=ready pod \
  --selector=app=ui --namespace=coin-ops --timeout=120s

success "Application services ready."

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 — Apply Ingress
# ─────────────────────────────────────────────────────────────────────────────
info "Applying Ingress routing..."
kubectl apply -f "${SCRIPT_DIR}/ingress.yaml"
success "Ingress applied."

# ─────────────────────────────────────────────────────────────────────────────
# STEP 7 — Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅  Coin Ops is running in k3d!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}URLs${NC}"
echo -e "  ─────────────────────────────────────────────────────"
echo -e "  UI          →  http://myapp.local/"
echo -e "  Proxy API   →  http://myapp.local/api/"
echo -e "  History API →  http://myapp.local/history-api/"
echo ""
echo -e "  ${CYAN}All pods${NC}"
echo -e "  ─────────────────────────────────────────────────────"
kubectl get pods -n coin-ops
echo ""
