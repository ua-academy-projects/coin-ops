#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_DIR="${ROOT_DIR}/k8s/headlamp"
TERRAFORM_DIR="${ROOT_DIR}/terraform.kubespray.aws"
HEADLAMP_NAMESPACE="headlamp"

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "${cmd} not found" >&2
    exit 1
  fi
}

require_command kubectl
require_command terraform

headlamp_nodeport="$(terraform -chdir="${TERRAFORM_DIR}" output -raw headlamp_nodeport)"
tmp_service="$(mktemp)"
trap 'rm -f "${tmp_service}"' EXIT

sed \
  -e "s#__HEADLAMP_NODEPORT__#${headlamp_nodeport}#g" \
  "${MANIFEST_DIR}/service.yaml" > "${tmp_service}"

kubectl apply -f "${MANIFEST_DIR}/namespace.yaml"
kubectl apply -f "${MANIFEST_DIR}/rbac.yaml"
kubectl apply -f "${MANIFEST_DIR}/deployment.yaml"
kubectl apply -f "${tmp_service}"
kubectl rollout restart deployment/headlamp -n "${HEADLAMP_NAMESPACE}"
kubectl rollout status deployment/headlamp -n "${HEADLAMP_NAMESPACE}" --timeout=180s

echo "Headlamp deployed."
echo "Namespace: ${HEADLAMP_NAMESPACE}"
echo "NodePort: ${headlamp_nodeport}"
echo
echo "Open a private tunnel first:"
terraform -chdir="${TERRAFORM_DIR}" output -raw headlamp_tunnel_command
echo
echo "Then open in browser:"
echo "http://127.0.0.1:30082"
