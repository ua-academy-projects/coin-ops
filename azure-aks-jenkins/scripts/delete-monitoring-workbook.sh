#!/usr/bin/env bash
set -euo pipefail

WORKBOOK_RESOURCE_GROUP="${1:-${WORKBOOK_RESOURCE_GROUP:-}}"
PROJECT_NAME="${2:-${PROJECT_NAME:-coin-ops}}"
ENVIRONMENT="${3:-${ENVIRONMENT:-dev}}"

log() {
  printf '[monitoring-workbook] %s\n' "$*"
}

if [[ -z "${WORKBOOK_RESOURCE_GROUP}" ]]; then
  log "Skipping monitoring workbook cleanup because WORKBOOK_RESOURCE_GROUP is empty."
  exit 0
fi

WORKBOOK_UUID="$(
  python3 - "${PROJECT_NAME}" "${ENVIRONMENT}" <<'PY'
import sys
import uuid

project_name, environment = sys.argv[1:3]
seed = f"{project_name}:{environment}:monitoring-workbook"
print(uuid.uuid5(uuid.NAMESPACE_DNS, seed))
PY
)"

if az monitor app-insights workbook show \
  --resource-group "${WORKBOOK_RESOURCE_GROUP}" \
  --name "${WORKBOOK_UUID}" \
  >/dev/null 2>&1; then
  log "Deleting monitoring workbook '${WORKBOOK_UUID}'."
  az monitor app-insights workbook delete \
    --resource-group "${WORKBOOK_RESOURCE_GROUP}" \
    --name "${WORKBOOK_UUID}" \
    --yes \
    >/dev/null
else
  log "Monitoring workbook '${WORKBOOK_UUID}' does not exist."
fi
