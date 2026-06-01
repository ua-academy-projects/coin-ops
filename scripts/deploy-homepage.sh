#!/usr/bin/env bash

set -euo pipefail

HOMEPAGE_HOST="${HOMEPAGE_HOST:-}"
HOMEPAGE_NAMESPACE="homepage"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_DIR="${ROOT_DIR}/k8s/homepage"
TERRAFORM_DIR="${ROOT_DIR}/terraform.kubespray.aws"
ENV_FILE="${ROOT_DIR}/.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

if [[ -z "${HOMEPAGE_HOST}" ]]; then
  echo "Usage: HOMEPAGE_HOST=homepage.example.com $0" >&2
  exit 1
fi

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "${cmd} not found" >&2
    exit 1
  fi
}

require_command kubectl
require_command terraform
require_command curl
require_command jq

ensure_cloudflare_dns() {
  local zone_name="${TF_VAR_cloudflare_zone_name:-}"
  local proxied="${TF_VAR_cloudflare_proxied:-true}"
  local api_token="${CLOUDFLARE_API_TOKEN:-}"
  local alb_dns_name zone_id record_id record_name payload response

  if [[ -z "${zone_name}" ]]; then
    echo "TF_VAR_cloudflare_zone_name is not set" >&2
    exit 1
  fi

  if [[ -z "${api_token}" ]]; then
    echo "CLOUDFLARE_API_TOKEN is not set" >&2
    exit 1
  fi

  case "${HOMEPAGE_HOST}" in
    *.${zone_name}|${zone_name})
      ;;
    *)
      echo "HOMEPAGE_HOST (${HOMEPAGE_HOST}) is not inside Cloudflare zone ${zone_name}" >&2
      exit 1
      ;;
  esac

  alb_dns_name="$(terraform -chdir="${TERRAFORM_DIR}" output -raw load_balancer_dns_name)"

  zone_id="$(
    curl -fsS \
      -H "Authorization: Bearer ${api_token}" \
      -H "Content-Type: application/json" \
      "https://api.cloudflare.com/client/v4/zones?name=${zone_name}" \
      | jq -r '.result[0].id // empty'
  )"

  if [[ -z "${zone_id}" ]]; then
    echo "Cloudflare zone ${zone_name} not found" >&2
    exit 1
  fi

  record_id="$(
    curl -fsS \
      -H "Authorization: Bearer ${api_token}" \
      -H "Content-Type: application/json" \
      "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records?type=CNAME&name=${HOMEPAGE_HOST}" \
      | jq -r '.result[0].id // empty'
  )"

  payload="$(
    jq -nc \
      --arg type "CNAME" \
      --arg name "${HOMEPAGE_HOST}" \
      --arg content "${alb_dns_name}" \
      --argjson proxied "${proxied}" \
      '{type: $type, name: $name, content: $content, ttl: 1, proxied: $proxied}'
  )"

  if [[ -n "${record_id}" ]]; then
    response="$(
      curl -fsS -X PUT \
        -H "Authorization: Bearer ${api_token}" \
        -H "Content-Type: application/json" \
        --data "${payload}" \
        "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records/${record_id}"
    )"
    record_name="updated"
  else
    response="$(
      curl -fsS -X POST \
        -H "Authorization: Bearer ${api_token}" \
        -H "Content-Type: application/json" \
        --data "${payload}" \
        "https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records"
    )"
    record_name="created"
  fi

  if [[ "$(jq -r '.success' <<<"${response}")" != "true" ]]; then
    echo "Cloudflare DNS ${record_name} failed" >&2
    jq -r '.errors' <<<"${response}" >&2
    exit 1
  fi

  echo "Cloudflare DNS ${record_name}: ${HOMEPAGE_HOST} -> ${alb_dns_name}"
}

tmp_ingress="$(mktemp)"
tmp_deployment="$(mktemp)"
trap 'rm -f "${tmp_ingress}" "${tmp_deployment}"' EXIT

sed \
  -e "s#__HOST__#${HOMEPAGE_HOST}#g" \
  -e "s#__NAMESPACE__#${HOMEPAGE_NAMESPACE}#g" \
  "${MANIFEST_DIR}/ingress.yaml.tmpl" > "${tmp_ingress}"

sed \
  -e "s#__HOST__#${HOMEPAGE_HOST}#g" \
  "${MANIFEST_DIR}/deployment.yaml" > "${tmp_deployment}"

kubectl apply -f "${MANIFEST_DIR}/namespace.yaml"
kubectl apply -f "${MANIFEST_DIR}/rbac.yaml"
kubectl apply -f "${MANIFEST_DIR}/configmap.yaml"
kubectl apply -f "${tmp_deployment}"
kubectl apply -f "${MANIFEST_DIR}/service.yaml"
kubectl apply -f "${tmp_ingress}"
kubectl rollout restart deployment/homepage -n "${HOMEPAGE_NAMESPACE}"
kubectl rollout status deployment/homepage -n "${HOMEPAGE_NAMESPACE}" --timeout=180s
ensure_cloudflare_dns

echo "Homepage deployed."
echo "Host: ${HOMEPAGE_HOST}"
echo "Namespace: ${HOMEPAGE_NAMESPACE}"
