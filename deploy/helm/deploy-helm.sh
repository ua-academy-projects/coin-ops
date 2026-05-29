#!/bin/bash
# =============================================================================
# deploy/helm/deploy-helm.sh
# =============================================================================
# Replaces the old Ansible playbook. Reads secrets from your local .env file
# and injects them securely into the Helm release without committing them.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ENV_FILE="${PROJECT_ROOT}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Error: .env not found at ${ENV_FILE}"
  exit 1
fi

# Load variables from .env
export $(grep -v '^#' "${ENV_FILE}" | grep -v '^$' | xargs)

# Ensure the KUBECONFIG is set (pointing to your Bastion tunnel)
if [[ -z "${KUBECONFIG}" ]]; then
  export KUBECONFIG="${PROJECT_ROOT}/terraform/k3s/.kube/config"
fi

echo "Deploying Coin-Ops via Helm..."

# Run helm upgrade --install with --set flags to inject secrets
cd "${SCRIPT_DIR}/coin-ops"

helm upgrade --install coin-ops . \
  --namespace coin-ops-infra \
  --create-namespace \
  --set global.env="${ENV:-production}" \
  --set image.registry="${IMAGE_REGISTRY:-ghcr.io/ua-academy-projects}" \
  --set image.tag="${IMAGE_TAG:-shabat-latest}" \
  --set image.pullSecret.username="${GHCR_USERNAME}" \
  --set image.pullSecret.password="${GHCR_TOKEN}" \
  --set routing.domain="${APP_DOMAIN}" \
  --set routing.nodeCidr="${NODE_CIDR:-10.10.1.0/24}" \
  --set cloudflare.tunnelToken="${CLOUDFLARE_TUNNEL_TOKEN}" \
  --set database.user="${DB_USER}" \
  --set database.password="${DB_PASSWORD}" \
  --set database.name="${DB_NAME}" \
  --set rabbitmq.auth.username="${RABBITMQ_USER}" \
  --set rabbitmq.auth.password="${RABBITMQ_PASSWORD}"

echo "Deployment complete! Use 'helm status coin-ops' to check the status."
