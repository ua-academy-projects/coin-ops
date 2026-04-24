#!/usr/bin/env bash
# smoke.sh — coin-ops end-to-end smoke suite.
#
# Intentionally small: boots the full stack on Docker Compose, waits for every
# service to become healthy, then runs a short list of confidence checks. If
# any check fails the script exits non-zero with a clear summary.
#
# Usage:
#   ./smoke.sh              # default: up → wait → check → down
#   ./smoke.sh up           # build images and start the stack, keep it running
#   ./smoke.sh check        # run checks against an already-running stack
#   ./smoke.sh down         # stop and remove the stack
#   ./smoke.sh logs [svc]   # tail logs (all services or just <svc>)
#
# Flags (default mode only):
#   --keep   don't tear the stack down after checks pass (useful for debugging)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.smoke.yaml"
GATEWAY_URL="${SMOKE_GATEWAY_URL:-http://localhost:18080}"
WAIT_TIMEOUT="${SMOKE_WAIT_TIMEOUT:-180}"
PROJECT_NAME="coin-ops-smoke"

# ── output helpers ──────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_DIM=$'\033[2m'
else
  C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_DIM=""
fi

step() { echo "${C_BLUE}▶${C_RESET} $*"; }
pass() { echo "${C_GREEN}✔${C_RESET} $*"; }
fail() { echo "${C_RED}✘${C_RESET} $*"; }
info() { echo "${C_DIM}  $*${C_RESET}"; }
warn() { echo "${C_YELLOW}!${C_RESET} $*"; }

# ── compose wrapper ─────────────────────────────────────────────────────────
compose() {
  docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" "$@"
}

# ── check registry ──────────────────────────────────────────────────────────
# Each check is a function that returns 0 (pass) / non-zero (fail).
# Register them in CHECKS to have them appear in the summary.
declare -a CHECKS=(
  "check_stack_healthy|Stack services are healthy"
  "check_proxy_health|Proxy /health responds 200"
  "check_history_health|History API /health responds 200"
  "check_gateway_health|Gateway /health responds 200"
  "check_ui_to_backend|UI → backend: GET /api/prices returns JSON"
  "check_history_read_path|History read-path: GET /history-api/history returns JSON array"
)

# Parallel indexed arrays — macOS still ships bash 3.2, which does not
# support associative arrays (`declare -A`).
CHECK_LABELS=()
CHECK_STATUSES=()

# ── wait helpers ────────────────────────────────────────────────────────────
wait_for_url() {
  local url="$1"; local name="$2"; local deadline=$((SECONDS + WAIT_TIMEOUT))
  while (( SECONDS < deadline )); do
    if curl -fsS --max-time 3 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  fail "timeout waiting for $name at $url"
  return 1
}

# Poll the gateway until the upstream routes are answering 200. `docker compose
# up --wait` only blocks on services that declare a `healthcheck:`. The Go
# proxy runs from a `scratch` image (no shell/wget/nc available for a
# container-level probe) and `history-consumer` is a queue worker with no HTTP
# surface, so both are gated only by `service_started`. Without this readiness
# loop, a raw curl immediately after `compose up --wait` can race the proxy's
# bind on :8080 and get a 502 from the gateway.
wait_for_gateway_ready() {
  wait_for_url "$GATEWAY_URL/health"              "gateway"                   || return 1
  wait_for_url "$GATEWAY_URL/api/health"          "proxy through gateway"     || return 1
  wait_for_url "$GATEWAY_URL/history-api/health"  "history-api through gateway" || return 1
  return 0
}

# ── checks ─────────────────────────────────────────────────────────────────
check_stack_healthy() {
  # All services with a healthcheck must be 'healthy'; services without one
  # (proxy on scratch, history-consumer) must at least be 'running'.
  local svc state health unhealthy=0
  while IFS=$'\t' read -r svc state health; do
    [[ -z "$svc" ]] && continue
    if [[ "$health" == "healthy" ]]; then
      info "$svc: healthy"
    elif [[ -z "$health" && "$state" == "running" ]]; then
      info "$svc: running (no healthcheck)"
    else
      fail "$svc: state=$state health=${health:-none}"
      unhealthy=1
    fi
  done < <(compose ps --format '{{.Service}}\t{{.State}}\t{{.Health}}')
  return "$unhealthy"
}

check_proxy_health() {
  local body status
  body="$(curl -fsS --max-time 5 -w '\n%{http_code}' "$GATEWAY_URL/api/health")" || {
    fail "curl $GATEWAY_URL/api/health failed"
    return 1
  }
  status="${body##*$'\n'}"; body="${body%$'\n'*}"
  [[ "$status" == "200" ]] || { fail "proxy /health status=$status"; return 1; }
  grep -q '"status"' <<<"$body" || { fail "proxy /health body missing status: $body"; return 1; }
  info "response: $body"
  return 0
}

check_history_health() {
  local body status
  body="$(curl -fsS --max-time 5 -w '\n%{http_code}' "$GATEWAY_URL/history-api/health")" || {
    fail "curl $GATEWAY_URL/history-api/health failed"
    return 1
  }
  status="${body##*$'\n'}"; body="${body%$'\n'*}"
  [[ "$status" == "200" ]] || { fail "history /health status=$status"; return 1; }
  grep -q '"status"' <<<"$body" || { fail "history /health body missing status: $body"; return 1; }
  info "response: $body"
  return 0
}

check_gateway_health() {
  local status
  status="$(curl -fsS --max-time 5 -o /dev/null -w '%{http_code}' "$GATEWAY_URL/health")" || {
    fail "curl $GATEWAY_URL/health failed"
    return 1
  }
  [[ "$status" == "200" ]] || { fail "gateway /health status=$status"; return 1; }
  return 0
}

check_ui_to_backend() {
  # /api/prices goes: curl → nginx gateway → proxy /prices. Verifies the same
  # routing layer the browser uses. Body may contain zeros if upstream data
  # providers are unreachable — we only assert the shape, not the values.
  local body status
  body="$(curl -fsS --max-time 10 -w '\n%{http_code}' "$GATEWAY_URL/api/prices")" || {
    fail "curl $GATEWAY_URL/api/prices failed"
    return 1
  }
  status="${body##*$'\n'}"; body="${body%$'\n'*}"
  [[ "$status" == "200" ]] || { fail "/api/prices status=$status"; return 1; }
  grep -q '"btc_usd"' <<<"$body" || {
    fail "/api/prices body missing 'btc_usd' key: $body"; return 1;
  }
  info "body contains btc_usd/eth_usd/usd_uah keys"
  return 0
}

check_history_read_path() {
  # /history-api/history goes: curl → gateway → history-api /history → psql
  # SELECT. Expect a JSON array (empty is fine — the consumer may not have
  # written anything yet; we only assert the read path works end-to-end).
  local body status
  body="$(curl -fsS --max-time 10 -w '\n%{http_code}' "$GATEWAY_URL/history-api/history?limit=1")" || {
    fail "curl $GATEWAY_URL/history-api/history failed"
    return 1
  }
  status="${body##*$'\n'}"; body="${body%$'\n'*}"
  [[ "$status" == "200" ]] || { fail "/history-api/history status=$status"; return 1; }
  [[ "${body:0:1}" == "[" ]] || { fail "/history-api/history did not return a JSON array: $body"; return 1; }
  info "response (first 120 chars): ${body:0:120}"
  return 0
}

# ── runtime write/read (documented as pending) ──────────────────────────────
# The PostgreSQL runtime path (RUNTIME_BACKEND=postgres, pgmq-backed queue) is
# not yet wired into the deployed stack per the roadmap in README.md. The
# acceptance criteria for this suite say this check is conditional on that
# work being available. When it lands, add a runtime check here and register
# it in CHECKS. Until then see runtime/tests/test_runtime.sql for the SQL-level
# acceptance tests that can be run standalone against a pgmq-enabled database.

# ── orchestration ──────────────────────────────────────────────────────────
cmd_up() {
  step "Building and starting stack (project=$PROJECT_NAME)"
  compose up -d --build --wait --wait-timeout "$WAIT_TIMEOUT"
  step "Waiting for gateway-proxied routes to answer"
  wait_for_gateway_ready || {
    fail "gateway was reachable but upstream routes never became ready"
    return 1
  }
  pass "stack is up and gateway routes are ready"
}

cmd_down() {
  step "Tearing stack down"
  compose down -v --remove-orphans
  pass "stack is down"
}

cmd_logs() {
  compose logs --no-log-prefix --tail=200 "${1:-}"
}

cmd_check() {
  # `cmd_up` already runs this readiness probe, but `cmd_check` is also invoked
  # standalone against a stack the user brought up manually, so re-run it here.
  # On an already-ready stack this costs one curl per route.
  wait_for_gateway_ready || return 1

  local total=0 failed=0
  for spec in "${CHECKS[@]}"; do
    local fn="${spec%%|*}"; local label="${spec#*|}"
    total=$((total + 1))
    step "$label"
    CHECK_LABELS+=("$label")
    if "$fn"; then
      pass "$label"
      CHECK_STATUSES+=("PASS")
    else
      fail "$label"
      CHECK_STATUSES+=("FAIL")
      failed=$((failed + 1))
    fi
    echo
  done

  echo "${C_BLUE}── summary ──${C_RESET}"
  local i=0
  while (( i < ${#CHECK_LABELS[@]} )); do
    if [[ "${CHECK_STATUSES[$i]}" == "PASS" ]]; then
      echo "  ${C_GREEN}PASS${C_RESET}  ${CHECK_LABELS[$i]}"
    else
      echo "  ${C_RED}FAIL${C_RESET}  ${CHECK_LABELS[$i]}"
    fi
    i=$((i + 1))
  done
  echo
  if (( failed == 0 )); then
    pass "$total/$total checks passed"
    return 0
  else
    fail "$failed/$total checks failed"
    return 1
  fi
}

# ── main ───────────────────────────────────────────────────────────────────
main() {
  local mode="${1:-all}"
  local keep=0
  shift || true
  for a in "$@"; do
    [[ "$a" == "--keep" ]] && keep=1
  done

  case "$mode" in
    up)    cmd_up ;;
    down)  cmd_down ;;
    logs)  cmd_logs "${1:-}" ;;
    check) cmd_check ;;
    all|"")
      cmd_up
      echo
      if cmd_check; then
        echo
        if (( keep )); then
          warn "--keep set: leaving stack running. Tear down with: $0 down"
        else
          cmd_down
        fi
        exit 0
      else
        echo
        warn "checks failed — stack left running for inspection."
        warn "  logs:     $0 logs"
        warn "  teardown: $0 down"
        exit 1
      fi
      ;;
    *)
      echo "usage: $0 [up|check|down|logs|all] [--keep]" >&2
      exit 2
      ;;
  esac
}

main "$@"
