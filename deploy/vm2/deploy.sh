#!/usr/bin/env bash
# VM2 — Backend + Worker auto-deploy
# Runs via crond every 60 seconds on Alpine Linux

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/ua-academy-projects/coin-ops.git}"
REPO_DIR="/opt/monero-privacy-system"
BACKEND_DIR="$REPO_DIR/backend"
VENV_DIR="/opt/monero-venv"
BRANCH="${DEPLOY_BRANCH:-main}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [VM2-DEPLOY] $*"; }

# ── Clone or update ──────────────────────────────────────────────────────────
if [ ! -d "$REPO_DIR/.git" ]; then
    log "Cloning repository..."
    git clone --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
    CHANGED=true
else
    cd "$REPO_DIR"
    git fetch origin "$BRANCH" --quiet

    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse "origin/$BRANCH")

    if [ "$LOCAL" = "$REMOTE" ]; then
        log "Already up to date ($LOCAL). Skipping."
        exit 0
    fi

    log "New commit: $LOCAL → $REMOTE"
    git pull origin "$BRANCH" --quiet
    CHANGED=true
fi

if [ "${CHANGED:-false}" = "true" ]; then
    # ── Create/update virtualenv ─────────────────────────────────────────────
    if [ ! -d "$VENV_DIR" ]; then
        log "Creating Python virtualenv..."
        python3 -m venv "$VENV_DIR"
    fi

    log "Installing Python dependencies..."
    "$VENV_DIR/bin/pip" install --quiet --upgrade pip
    "$VENV_DIR/bin/pip" install --quiet -r "$BACKEND_DIR/requirements.txt"

    # ── Run DB migrations ────────────────────────────────────────────────────
    log "Applying database schema..."
    PGPASSWORD="${DB_PASSWORD:-monero}" psql \
        -h "${DB_HOST:-db}" \
        -U "${DB_USER:-monero}" \
        -d "${DB_NAME:-monero_privacy}" \
        -f "$REPO_DIR/database/schema.sql" \
        --quiet || log "Schema apply warning (may already exist)"

    # ── Restart services (OpenRC) ────────────────────────────────────────────
    log "Restarting monero-api..."
    rc-service monero-api restart 2>/dev/null || rc-service monero-api start

    log "Restarting monero-worker..."
    rc-service monero-worker restart 2>/dev/null || rc-service monero-worker start

    log "Waiting for API health check..."
    sleep 3
    if curl -sf http://localhost:8000/health > /dev/null; then
        log "API is healthy ✓"
    else
        log "WARNING: API health check failed"
    fi

    log "Deploy complete. Commit: $(git -C "$REPO_DIR" rev-parse --short HEAD)"
fi
