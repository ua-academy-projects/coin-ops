#!/usr/bin/env bash
# =============================================================================
# deploy/local/app/build-local.sh
# =============================================================================
# Builds the Coin Ops images locally (using your Mac's native architecture,
# e.g., arm64) and imports them into the k3d cluster.
#
# This solves the "no match for platform in manifest" error when trying to
# run amd64 images from GHCR on an Apple Silicon Mac. It also enables a fast
# local development loop without pushing code to GitHub.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }

info "Building proxy..."
docker build -t coin-ops-proxy:local "${PROJECT_ROOT}/proxy"

info "Building history-api..."
docker build -t coin-ops-history-api:local -f "${PROJECT_ROOT}/history/Dockerfile.api" "${PROJECT_ROOT}/history"

info "Building history-consumer..."
docker build -t coin-ops-history-consumer:local -f "${PROJECT_ROOT}/history/Dockerfile.consumer" "${PROJECT_ROOT}/history"

info "Building ui..."
docker build -t coin-ops-ui:local "${PROJECT_ROOT}/ui-react"

info "Importing images into k3d cluster 'coin-ops-local'..."
k3d image import coin-ops-proxy:local coin-ops-history-api:local coin-ops-history-consumer:local coin-ops-ui:local -c coin-ops-local

success "Local images built and imported."
info "Restarting deployments to pick up the new images..."
kubectl rollout restart deployment proxy history-api history-consumer ui -n coin-ops || true
success "Deployments restarted."
