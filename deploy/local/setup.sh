#!/usr/bin/env bash
# =============================================================================
# deploy/local/setup.sh
# =============================================================================
# One-shot script to spin up a local k3d cluster with Headlamp and deploy
# the coin-ops microservices for local development.
#
# Prerequisites (install once):
#   brew install k3d kubectl helm
#
# Usage:
#   chmod +x deploy/local/setup.sh
#   ./deploy/local/setup.sh
# =============================================================================

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
CLUSTER_NAME="coin-ops-local"
LOCAL_DOMAIN="myapp.local"
MANIFESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Terminal colours
GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }

# ─────────────────────────────────────────────────────────────────────────────
# STEP 0 — Preflight checks
# ─────────────────────────────────────────────────────────────────────────────
info "Checking prerequisites..."
for cmd in k3d kubectl helm docker; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "  ✗ '$cmd' not found. Install it first:"
    echo "    brew install $cmd"
    exit 1
  fi
  echo "  ✓ $cmd $(${cmd} version --short 2>/dev/null || ${cmd} version 2>/dev/null | head -1)"
done

if ! docker info &>/dev/null; then
  echo "  ✗ Docker daemon is not running. Start Docker Desktop first."
  exit 1
fi
success "All prerequisites satisfied."

# ─────────────────────────────────────────────────────────────────────────────
# STEP 1 — Create k3d cluster
# ─────────────────────────────────────────────────────────────────────────────
info "Creating k3d cluster '${CLUSTER_NAME}'..."

if k3d cluster list | grep -q "^${CLUSTER_NAME}"; then
  warn "Cluster '${CLUSTER_NAME}' already exists — skipping creation."
  warn "To recreate: k3d cluster delete ${CLUSTER_NAME} && re-run this script."
else
  k3d cluster create "${CLUSTER_NAME}" \
    --servers 1 \
    --agents 2 \
    --port "80:80@loadbalancer" \
    --port "443:443@loadbalancer" \
    --port "8080:8080@loadbalancer" \
    --wait
  success "Cluster created."
fi

# Merge kubeconfig and switch context
k3d kubeconfig merge "${CLUSTER_NAME}" --kubeconfig-switch-context
success "kubectl context switched to k3d-${CLUSTER_NAME}."

# ─────────────────────────────────────────────────────────────────────────────
# STEP 2 — Wait for core system Deployments to be available
# ─────────────────────────────────────────────────────────────────────────────
# NOTE: We wait on *Deployments*, not Pods.
#   k3s bootstraps Traefik and metrics-server via one-off Kubernetes Jobs
#   (helm-install-traefik-*, helm-install-traefik-crd-*). Those Jobs exit with
#   status "Succeeded" — they are never "Ready" — so `kubectl wait pod --all`
#   always times out on them. Waiting on Deployments correctly skips Jobs and
#   only checks that the actual workload replicas are healthy.
info "Waiting for system Deployments to become available (up to 180 s)..."
kubectl wait deployment \
  --all --namespace kube-system \
  --for=condition=available \
  --timeout=180s
success "System Deployments available."

# ─────────────────────────────────────────────────────────────────────────────
# STEP 3 — Install Headlamp (macOS Desktop App via Homebrew)
# ─────────────────────────────────────────────────────────────────────────────
# The Headlamp Helm chart (both GitHub Pages and OCI ghcr.io) requires auth.
# The Desktop App is the recommended approach for local dev:
#   • Reads your kubeconfig automatically — no in-cluster components needed.
#   • No port-forward, no token required for local clusters.
#   • Opens natively as a macOS app.
info "Installing Headlamp Desktop App..."
if ! brew list --cask headlamp &>/dev/null; then
  brew install --cask headlamp
  success "Headlamp desktop app installed."
else
  warn "Headlamp desktop app already installed — skipping."
fi

success "Headlamp installed."

# Apply the headlamp admin SA + RBAC
kubectl apply -f "${MANIFESTS_DIR}/headlamp.yaml"
success "Headlamp ServiceAccount created."

# ─────────────────────────────────────────────────────────────────────────────
# STEP 4 — Deploy application manifests
# ─────────────────────────────────────────────────────────────────────────────
info "Deploying coin-ops manifests..."
kubectl apply -f "${MANIFESTS_DIR}/namespace.yaml"
kubectl apply -f "${MANIFESTS_DIR}/frontend.yaml"
kubectl apply -f "${MANIFESTS_DIR}/backend.yaml"

info "Waiting for application Pods..."
kubectl wait --for=condition=ready pod \
  --selector=app=frontend \
  --namespace=coin-ops \
  --timeout=90s
kubectl wait --for=condition=ready pod \
  --selector=app=backend \
  --namespace=coin-ops \
  --timeout=90s

kubectl apply -f "${MANIFESTS_DIR}/ingress.yaml"
success "Application deployed."

# ─────────────────────────────────────────────────────────────────────────────
# STEP 5 — /etc/hosts entry
# ─────────────────────────────────────────────────────────────────────────────
HOSTS_ENTRY="127.0.0.1  ${LOCAL_DOMAIN}"
if grep -q "${LOCAL_DOMAIN}" /etc/hosts; then
  warn "/etc/hosts already contains '${LOCAL_DOMAIN}' — skipping."
else
  echo "Adding '${HOSTS_ENTRY}' to /etc/hosts (requires sudo)..."
  echo "${HOSTS_ENTRY}" | sudo tee -a /etc/hosts > /dev/null
  success "/etc/hosts updated."
fi

# ─────────────────────────────────────────────────────────────────────────────
# STEP 6 — Generate Headlamp token (fallback if the app asks for one)
# ─────────────────────────────────────────────────────────────────────────────
info "Generating Headlamp bearer token (in case the app requests one)..."
HEADLAMP_TOKEN=$(kubectl create token headlamp-admin \
  --namespace kube-system \
  --duration=8760h 2>/dev/null || \
  kubectl get secret \
    "$(kubectl get serviceaccount headlamp-admin -n kube-system \
       -o jsonpath='{.secrets[0].name}')" \
    -n kube-system \
    -o jsonpath='{.data.token}' | base64 --decode)

# ─────────────────────────────────────────────────────────────────────────────
# STEP 7 — Print summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅  Local k3d environment is ready!${NC}"
echo -e "${GREEN}══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}Application URLs${NC}"
echo -e "  ─────────────────────────────────────────────────────"
echo -e "  Frontend  →  http://${LOCAL_DOMAIN}/"
echo -e "  Backend   →  http://${LOCAL_DOMAIN}/api/"
echo ""
echo -e "  ${CYAN}Headlamp Dashboard (Desktop App)${NC}"
echo -e "  ─────────────────────────────────────────────────────"
echo -e "  1. Open Headlamp from Spotlight / Applications."
echo -e "     (It auto-detects k3d-coin-ops-local from your kubeconfig)"
echo -e "  2. If Headlamp asks for a token, paste:"
echo ""
echo -e "${YELLOW}${HEADLAMP_TOKEN}${NC}"
echo ""
echo -e "  ${CYAN}Useful commands${NC}"
echo -e "  ─────────────────────────────────────────────────────"
echo -e "  kubectl get pods -n coin-ops"
echo -e "  kubectl get ingress -n coin-ops"
echo -e "  k3d cluster stop ${CLUSTER_NAME}    # pause"
echo -e "  k3d cluster start ${CLUSTER_NAME}   # resume"
echo -e "  k3d cluster delete ${CLUSTER_NAME}  # tear down"
echo ""
