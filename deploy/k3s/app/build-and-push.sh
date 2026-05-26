#!/usr/bin/env bash
# =============================================================================
# deploy/k3s/app/build-and-push.sh
# =============================================================================
# Builds the Coin Ops images locally (using your Mac's native architecture,
# e.g., arm64), tags them, and pushes them to your remote container registry.
#
# Then executes a rollout restart to trigger the cloud cluster to pull the
# fresh images.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()     { echo -e "${RED}[ERR]${NC}   $*"; exit 1; }

# ── 1. Load .env ─────────────────────────────────────────────────────────────
[[ -f "${ENV_FILE}" ]] || err ".env not found at ${ENV_FILE}. Sourced registry coordinates required."
# shellcheck disable=SC2046
export $(grep -v '^#' "${ENV_FILE}" | grep -v '^$' | xargs)

IMAGE_REGISTRY="${IMAGE_REGISTRY:-ghcr.io/ua-academy-projects}"
IMAGE_TAG="${IMAGE_TAG:-shabat-latest}"
GHCR_USERNAME="${GHCR_USERNAME:-}"
GHCR_TOKEN="${GHCR_TOKEN:-}"
PREFIX="${PREFIX:-coin-ops}"
APP_NAMESPACE="${PREFIX}-app"

# ── 2. Registry login ─────────────────────────────────────────────────────────
if [[ -n "${GHCR_USERNAME}" && -n "${GHCR_TOKEN}" ]]; then
  info "Logging in to container registry..."
  echo "${GHCR_TOKEN}" | docker login ghcr.io -u "${GHCR_USERNAME}" --password-stdin || err "Docker registry login failed."
  success "Logged in to ghcr.io."
else
  warn "No registry credentials found. Assuming public registry or pre-established docker authentication."
fi

# ── 3. Build Images ───────────────────────────────────────────────────────────
info "Building Go Proxy Gateway..."
docker build -t "${IMAGE_REGISTRY}/coin-ops-proxy:${IMAGE_TAG}" "${PROJECT_ROOT}/proxy"

info "Building FastAPI History API..."
docker build -t "${IMAGE_REGISTRY}/coin-ops-history-api:${IMAGE_TAG}" -f "${PROJECT_ROOT}/history/Dockerfile.api" "${PROJECT_ROOT}/history"

info "Building Python History Consumer..."
docker build -t "${IMAGE_REGISTRY}/coin-ops-history-consumer:${IMAGE_TAG}" -f "${PROJECT_ROOT}/history/Dockerfile.consumer" "${PROJECT_ROOT}/history"

info "Building React Web UI..."
docker build -t "${IMAGE_REGISTRY}/coin-ops-ui:${IMAGE_TAG}" "${PROJECT_ROOT}/ui-react"

success "Images built and tagged successfully."

# ── 4. Push Images ────────────────────────────────────────────────────────────
info "Pushing images to registry: ${IMAGE_REGISTRY}..."
docker push "${IMAGE_REGISTRY}/coin-ops-proxy:${IMAGE_TAG}"
docker push "${IMAGE_REGISTRY}/coin-ops-history-api:${IMAGE_TAG}"
docker push "${IMAGE_REGISTRY}/coin-ops-history-consumer:${IMAGE_TAG}"
docker push "${IMAGE_REGISTRY}/coin-ops-ui:${IMAGE_TAG}"

success "Images pushed successfully."

# ── 5. Trigger Rollout Restart ────────────────────────────────────────────────
info "Triggering rollout restart on K3s cloud cluster to pull fresh images..."
export KUBECONFIG="${PROJECT_ROOT}/terraform/k3s/.kube/config"

kubectl rollout restart deployment proxy history-api history-consumer ui -n "${APP_NAMESPACE}" || warn "Could not perform cluster rollout. Ensure deploy.sh has been run first."

success "Deployments rollout restart triggered."
