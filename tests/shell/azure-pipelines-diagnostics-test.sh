#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
scripts="$repo_root/terraform/multicloud-vm-yaml-lab/scripts/azure-pipelines"

grep -Fq '(r.get("log") or {}).get("id","")' "$scripts/show-failures.sh"
grep -Fq 'result = row.get("result") or "pending"' "$scripts/watch-run.sh"
grep -Fq '[[ "$status" == "completed" && "$result" != "pending" ]]' "$scripts/watch-run.sh"

bash -n "$scripts/show-failures.sh"
bash -n "$scripts/watch-run.sh"

echo "Azure pipeline diagnostics handle null logs and result consistency lag"
