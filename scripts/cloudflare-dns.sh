#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "upsert" ]]; then
  echo "Usage: $0 upsert <record-name> <ipv4-address>" >&2
  exit 1
fi

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" || -z "${CLOUDFLARE_ZONE_ID:-}" ]]; then
  echo "CLOUDFLARE_API_TOKEN and CLOUDFLARE_ZONE_ID must be set." >&2
  exit 1
fi

if [[ $# -ne 3 ]]; then
  echo "Usage: $0 upsert <record-name> <ipv4-address>" >&2
  exit 1
fi

record_name="$2"
record_ip="$3"
api_base="https://api.cloudflare.com/client/v4"

auth_header="Authorization: Bearer ${CLOUDFLARE_API_TOKEN}"
content_header="Content-Type: application/json"

response="$(curl --fail --silent --show-error \
  -H "${auth_header}" \
  "${api_base}/zones/${CLOUDFLARE_ZONE_ID}/dns_records?type=A&name=${record_name}")"

record_id="$(python3 -c 'import json,sys; data=json.load(sys.stdin); result=data.get("result", []); print(result[0]["id"] if result else "")' <<<"${response}")"

payload="$(python3 -c 'import json,sys; print(json.dumps({"type":"A","name":sys.argv[1],"content":sys.argv[2],"ttl":1,"proxied":True}))' "${record_name}" "${record_ip}")"

if [[ -n "${record_id}" ]]; then
  curl --fail --silent --show-error \
    -X PUT \
    -H "${auth_header}" \
    -H "${content_header}" \
    --data "${payload}" \
    "${api_base}/zones/${CLOUDFLARE_ZONE_ID}/dns_records/${record_id}" >/dev/null
  echo "Updated Cloudflare DNS record ${record_name} -> ${record_ip}"
else
  curl --fail --silent --show-error \
    -X POST \
    -H "${auth_header}" \
    -H "${content_header}" \
    --data "${payload}" \
    "${api_base}/zones/${CLOUDFLARE_ZONE_ID}/dns_records" >/dev/null
  echo "Created Cloudflare DNS record ${record_name} -> ${record_ip}"
fi
