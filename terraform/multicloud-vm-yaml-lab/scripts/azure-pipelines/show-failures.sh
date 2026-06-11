#!/usr/bin/env bash
set -euo pipefail
test -s /tmp/coinops-ado-pat
pat="$(< /tmp/coinops-ado-pat)"
run_id="${1:?usage: show_ado_failures.sh RUN_ID}"
base="https://dev.azure.com/coinops-leev1tan/CoinOps/_apis/build/builds/$run_id"
timeline="$(curl --fail --silent --show-error --user ":$pat" "$base/timeline?api-version=7.1")"

mapfile -t failed_logs < <(python3 -c 'import json,sys; rows=json.load(sys.stdin).get("records", []); [print("{}\t{}\t{}".format(r.get("type",""),r.get("name",""),(r.get("log") or {}).get("id",""))) for r in rows if r.get("result") == "failed" and (r.get("log") or {}).get("id")]' <<<"$timeline")

for entry in "${failed_logs[@]}"; do
  IFS=$'\t' read -r type name log_id <<<"$entry"
  printf '\n===== %s: %s (log %s) =====\n' "$type" "$name" "$log_id"
  curl --fail --silent --show-error --user ":$pat" "$base/logs/$log_id?api-version=7.1" | tail -n 160
done
