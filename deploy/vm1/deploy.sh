#!/usr/bin/env bash
# VM1 — Frontend auto-deploy
# Runs via crond every 60 seconds on Alpine Linux

set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/ua-academy-projects/coin-ops.git}"
REPO_DIR="/opt/monero-privacy-system"
FRONTEND_DIR="$REPO_DIR/frontend"
WEB_ROOT="/var/www/monero-frontend"
BRANCH="${DEPLOY_BRANCH:-monero-privacy-system}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [VM1-DEPLOY] $*"; }

# ── Clone or update ──────────────────────────────────────────────────────────
if [ ! -d "$REPO_DIR/.git" ]; then
    log "Cloning repository..."
    git clone --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
    CHANGED=true
else
    log "Fetching updates..."
    cd "$REPO_DIR"
    git fetch origin "$BRANCH" --quiet

    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse "origin/$BRANCH")

    if [ "$LOCAL" = "$REMOTE" ]; then
        log "Already up to date ($LOCAL). Skipping."
        exit 0
    fi

    log "New commit detected: $LOCAL → $REMOTE"
    git pull origin "$BRANCH" --quiet
    CHANGED=true
fi

# ── Build frontend ───────────────────────────────────────────────────────────
if [ "${CHANGED:-false}" = "true" ]; then
    log "Installing npm dependencies..."
    cd "$FRONTEND_DIR"
    npm ci --silent

    log "Building React app..."
    REACT_APP_API_URL="${REACT_APP_API_URL:-http://backend:8000}" npm run build

    log "Deploying to web root..."
    mkdir -p "$WEB_ROOT"
    rsync -a --delete "$FRONTEND_DIR/build/" "$WEB_ROOT/"

    log "Reloading nginx..."
    sudo rc-service nginx reload

    log "Deploy complete. Commit: $(git -C "$REPO_DIR" rev-parse --short HEAD)"
fi
