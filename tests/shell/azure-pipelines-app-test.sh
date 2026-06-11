#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
pipeline="$repo_root/azure-pipelines-app.yml"

test -f "$pipeline"
if ! grep -Fq 'docker build -t coinops-postgres-runtime:latest' "$pipeline"; then
  echo "Azure Pipelines does not build the PostgreSQL image tag expected by the integration fixture" >&2
  exit 1
fi
if grep -Fq 'docker build -t coinops-postgres-runtime:test' "$pipeline"; then
  echo "Azure Pipelines builds a different PostgreSQL image tag than the integration fixture uses" >&2
  exit 1
fi

echo "Azure application pipeline PostgreSQL test-image contract is complete"
