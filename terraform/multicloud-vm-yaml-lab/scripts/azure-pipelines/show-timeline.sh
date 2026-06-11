#!/usr/bin/env bash
set -euo pipefail
test -s /tmp/coinops-ado-pat
pat="$(< /tmp/coinops-ado-pat)"
run_id="${1:?usage: show_ado_timeline.sh RUN_ID}"
curl --fail --silent --show-error --user ":$pat" \
  "https://dev.azure.com/coinops-leev1tan/CoinOps/_apis/build/builds/$run_id/timeline?api-version=7.1" \
  | python3 -c 'import json,sys; rows=json.load(sys.stdin).get("records", []); print("TYPE\tNAME\tSTATE\tRESULT"); [print("{}\t{}\t{}\t{}".format(r.get("type",""),r.get("name",""),r.get("state",""),r.get("result",""))) for r in rows if r.get("type") in ("Stage","Job")];'
