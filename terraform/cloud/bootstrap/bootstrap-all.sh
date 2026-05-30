#!/usr/bin/env bash
# Run all cloud bootstrap scripts while creating backend storage in one cloud only.
#
# Usage:
#   ./bootstrap-all.sh gcp
#   ./bootstrap-all.sh azure
#   ./bootstrap-all.sh aws

set -euo pipefail

BACKEND="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "${BACKEND}" != "gcp" && "${BACKEND}" != "azure" && "${BACKEND}" != "aws" ]]; then
  echo "Usage: $0 <gcp|azure|aws>"
  exit 1
fi

echo "Backend owner: ${BACKEND}"

echo ""
echo "==> GCP bootstrap"
CREATE_BACKEND="$([[ "${BACKEND}" == "gcp" ]] && echo true || echo false)" \
  ENV_FILE="${SCRIPT_DIR}/gcp.env" \
  BACKEND_CONFIG_FILE="${SCRIPT_DIR}/backend.gcp.hcl" \
  bash "${SCRIPT_DIR}/gcp-bootstrap.sh"

echo ""
echo "==> Azure bootstrap"
CREATE_BACKEND="$([[ "${BACKEND}" == "azure" ]] && echo true || echo false)" \
  CREDENTIALS_FILE="${SCRIPT_DIR}/azure.env" \
  BACKEND_CONFIG_FILE="${SCRIPT_DIR}/backend.azure.hcl" \
  bash "${SCRIPT_DIR}/azure-bootstrap.sh"

echo ""
echo "==> AWS bootstrap"
CREATE_BACKEND="$([[ "${BACKEND}" == "aws" ]] && echo true || echo false)" \
  ENV_FILE="${SCRIPT_DIR}/aws.env" \
  BACKEND_CONFIG_FILE="${SCRIPT_DIR}/backend.aws.hcl" \
  bash "${SCRIPT_DIR}/aws-bootstrap.sh"

echo ""
echo "Done. Backend storage was created only for: ${BACKEND}"
