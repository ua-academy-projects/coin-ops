#!/usr/bin/env bash
# =============================================================================
# deploy/local/teardown.sh
# =============================================================================
# Cleanly removes the local k3d cluster and the /etc/hosts entry.
# =============================================================================

set -euo pipefail

CLUSTER_NAME="coin-ops-local"
LOCAL_DOMAIN="myapp.local"

echo "Deleting k3d cluster '${CLUSTER_NAME}'..."
k3d cluster delete "${CLUSTER_NAME}" 2>/dev/null || echo "  (cluster not found)"

echo "Removing '${LOCAL_DOMAIN}' from /etc/hosts (requires sudo)..."
sudo sed -i '' "/[[:space:]]${LOCAL_DOMAIN}/d" /etc/hosts 2>/dev/null || true

echo "Done. All local resources removed."
