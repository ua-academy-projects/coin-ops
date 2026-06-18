#!/usr/bin/env bash
set -euo pipefail

WORKBOOK_RESOURCE_GROUP="${1:-${WORKBOOK_RESOURCE_GROUP:-}}"
WORKBOOK_LOCATION="${2:-${WORKBOOK_LOCATION:-}}"
WORKSPACE_ID="${3:-${WORKSPACE_ID:-}}"
AKS_CLUSTER_NAME="${4:-${AKS_CLUSTER_NAME:-}}"
APP_NAMESPACE="${5:-${APP_NAMESPACE:-apps}}"
PROJECT_NAME="${6:-${PROJECT_NAME:-coin-ops}}"
ENVIRONMENT="${7:-${ENVIRONMENT:-dev}}"

log() {
  printf '[monitoring-workbook] %s\n' "$*"
}

fail() {
  printf '[monitoring-workbook] ERROR: %s\n' "$*" >&2
  exit 1
}

require_value() {
  local name="$1"
  local value="$2"

  if [[ -z "${value}" ]]; then
    fail "Missing required value: ${name}"
  fi
}

require_value "WORKBOOK_RESOURCE_GROUP" "${WORKBOOK_RESOURCE_GROUP}"
require_value "WORKBOOK_LOCATION" "${WORKBOOK_LOCATION}"
require_value "WORKSPACE_ID" "${WORKSPACE_ID}"
require_value "AKS_CLUSTER_NAME" "${AKS_CLUSTER_NAME}"

WORKBOOK_UUID="$(
  python3 - "${PROJECT_NAME}" "${ENVIRONMENT}" <<'PY'
import sys
import uuid

project_name, environment = sys.argv[1:3]
seed = f"{project_name}:{environment}:monitoring-workbook"
print(uuid.uuid5(uuid.NAMESPACE_DNS, seed))
PY
)"

WORKBOOK_DISPLAY_NAME="${PROJECT_NAME}-${ENVIRONMENT}-monitoring"
TMP_SERIALIZED_DATA="$(mktemp)"
trap 'rm -f "${TMP_SERIALIZED_DATA}"' EXIT

python3 - "${WORKSPACE_ID}" "${AKS_CLUSTER_NAME}" "${APP_NAMESPACE}" "${WORKBOOK_DISPLAY_NAME}" >"${TMP_SERIALIZED_DATA}" <<'PY'
import json
import sys

workspace_id, cluster_name, app_namespace, workbook_title = sys.argv[1:5]

def kql_item(title: str, query: str) -> dict:
    return {
        "type": 3,
        "content": {
            "version": "KqlItem/1.0",
            "query": query,
            "size": 0,
            "title": title,
            "queryType": 0,
            "resourceType": "microsoft.operationalinsights/workspaces",
            "crossComponentResources": [workspace_id],
            "visualization": "timechart",
            "timeContext": {
                "durationMs": 21600000
            }
        },
        "name": title.lower().replace(" ", "-")
    }

items = [
    {
        "type": 1,
        "content": {
            "json": (
                f"# {workbook_title}\n"
                "Three AKS monitoring charts provisioned by bootstrap."
            )
        },
        "name": "overview"
    },
    kql_item(
        "AKS Node CPU",
        (
            "Perf "
            "| where ObjectName == 'K8SNode' "
            "| where CounterName == 'cpuUsagePercentage' "
            "| summarize AvgCpu = avg(CounterValue) by bin(TimeGenerated, 5m) "
            "| render timechart"
        ),
    ),
    kql_item(
        "Not Ready Nodes",
        (
            f"KubeNodeInventory "
            f"| where ClusterName =~ '{cluster_name}' "
            "| summarize NotReadyNodes = dcountif(Computer, Status != 'Ready') by bin(TimeGenerated, 5m) "
            "| render timechart"
        ),
    ),
    kql_item(
        "Problem Pods",
        (
            f"KubePodInventory "
            f"| where ClusterName =~ '{cluster_name}' "
            f"| where Namespace == '{app_namespace}' "
            "| where PodStatus in ('Pending', 'Failed', 'Unknown') "
            "| summarize ProblemPods = dcount(Name) by bin(TimeGenerated, 5m) "
            "| render timechart"
        ),
    ),
]

workbook = {
    "version": "Notebook/1.0",
    "items": items,
    "fallbackResourceIds": [workspace_id],
}

print(json.dumps(workbook))
PY

if az monitor app-insights workbook show \
  --resource-group "${WORKBOOK_RESOURCE_GROUP}" \
  --name "${WORKBOOK_UUID}" \
  >/dev/null 2>&1; then
  log "Updating monitoring workbook '${WORKBOOK_DISPLAY_NAME}'."
  az monitor app-insights workbook update \
    --resource-group "${WORKBOOK_RESOURCE_GROUP}" \
    --name "${WORKBOOK_UUID}" \
    --display-name "${WORKBOOK_DISPLAY_NAME}" \
    --category workbook \
    --kind shared \
    --source-id "${WORKSPACE_ID}" \
    --version Notebook/1.0 \
    --serialized-data "$(cat "${TMP_SERIALIZED_DATA}")" \
    >/dev/null
else
  log "Creating monitoring workbook '${WORKBOOK_DISPLAY_NAME}'."
  az monitor app-insights workbook create \
    --resource-group "${WORKBOOK_RESOURCE_GROUP}" \
    --location "${WORKBOOK_LOCATION}" \
    --name "${WORKBOOK_UUID}" \
    --display-name "${WORKBOOK_DISPLAY_NAME}" \
    --category workbook \
    --kind shared \
    --source-id "${WORKSPACE_ID}" \
    --version Notebook/1.0 \
    --serialized-data "$(cat "${TMP_SERIALIZED_DATA}")" \
    >/dev/null
fi

log "Workbook ready: ${WORKBOOK_DISPLAY_NAME} (${WORKBOOK_UUID})"
