#!/usr/bin/env bash
# bootstrap.sh — Run once on each VM to install all dependencies and configure services.
# Target OS: Alpine Linux (uses apk, OpenRC, crond)
# Usage: sudo bash bootstrap.sh [vm1|vm2|vm3]

set -euo pipefail

VM_ROLE="${1:-}"
if [[ -z "$VM_ROLE" ]]; then
    echo "Usage: sudo bash bootstrap.sh [vm1|vm2|vm3]"
    exit 1
fi

log() { echo -e "\n\033[1;33m[BOOTSTRAP:$VM_ROLE]\033[0m $*"; }
ok()  { echo -e "\033[1;32m  ✓ $*\033[0m"; }

# ── Common setup ─────────────────────────────────────────────────────────────
log "Updating system packages..."
apk update && apk upgrade

log "Installing common tools..."
apk add --no-cache git curl rsync bash openssl

# ── Create deploy user ───────────────────────────────────────────────────────
if ! id deploy &>/dev/null; then
    adduser -D -s /bin/bash deploy
    ok "Created deploy user"
fi

mkdir -p /etc/monero
mkdir -p /opt/monero-scripts

# ─────────────────────────────────────────────────────────────────────────────
# VM1 — Frontend
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$VM_ROLE" == "vm1" ]]; then
    log "Installing Node.js and Nginx..."
    apk add --no-cache nodejs npm nginx
    ok "Node $(node --version) installed"
    ok "Nginx installed"

    log "Configuring nginx..."
    mkdir -p /var/www/monero-frontend
    cp /opt/monero-scripts/nginx.conf /etc/nginx/http.d/monero.conf
    rm -f /etc/nginx/http.d/default.conf
    nginx -t && rc-update add nginx default && rc-service nginx start
    ok "Nginx configured and started"

    log "Installing deploy service..."
    cp /opt/monero-scripts/monero-deploy-frontend /etc/init.d/monero-deploy-frontend
    chmod +x /etc/init.d/monero-deploy-frontend
    cp /opt/monero-scripts/deploy.sh /opt/monero-scripts/deploy.sh
    chmod +x /opt/monero-scripts/deploy.sh

    # Set up crond for auto-deploy every minute
    log "Setting up cron for auto-deploy..."
    echo "* * * * * deploy /opt/monero-scripts/deploy.sh >> /var/log/monero-deploy.log 2>&1" >> /etc/crontabs/root
    rc-update add crond default
    rc-service crond start
    ok "Auto-deploy cron enabled (every 60s)"

    log "Running initial deploy..."
    bash /opt/monero-scripts/deploy.sh || log "Initial deploy needs REACT_APP_API_URL set in /etc/monero/deploy.env"
fi

# ─────────────────────────────────────────────────────────────────────────────
# VM2 — Backend + Worker
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$VM_ROLE" == "vm2" ]]; then
    log "Installing Python 3 and build dependencies..."
    apk add --no-cache python3 python3-dev py3-pip py3-virtualenv build-base postgresql-client libpq-dev

    log "Creating monero system user..."
    if ! id monero &>/dev/null; then
        adduser -D -S -s /sbin/nologin -h /opt/monero-privacy-system monero
    fi
    ok "monero user ready"

    log "Installing deploy service..."
    cp /opt/monero-scripts/monero-deploy-backend /etc/init.d/monero-deploy-backend
    chmod +x /etc/init.d/monero-deploy-backend
    cp /opt/monero-scripts/deploy.sh /opt/monero-scripts/deploy.sh
    chmod +x /opt/monero-scripts/deploy.sh

    log "Installing API + Worker services..."
    cp /opt/monero-scripts/monero-api /etc/init.d/monero-api
    cp /opt/monero-scripts/monero-worker /etc/init.d/monero-worker
    chmod +x /etc/init.d/monero-api /etc/init.d/monero-worker

    rc-update add monero-api default
    rc-update add monero-worker default
    ok "Services registered with OpenRC"

    # Set up crond for auto-deploy every minute
    log "Setting up cron for auto-deploy..."
    echo "* * * * * root /opt/monero-scripts/deploy.sh >> /var/log/monero-deploy.log 2>&1" >> /etc/crontabs/root
    rc-update add crond default
    rc-service crond start
    ok "Auto-deploy cron enabled (every 60s)"

    log "Running initial deploy..."
    bash /opt/monero-scripts/deploy.sh || log "Initial deploy needs /etc/monero/backend.env configured"
fi

# ─────────────────────────────────────────────────────────────────────────────
# VM3 — Database
# ─────────────────────────────────────────────────────────────────────────────
if [[ "$VM_ROLE" == "vm3" ]]; then
    log "Installing PostgreSQL..."
    apk add --no-cache postgresql postgresql-client

    log "Initialising PostgreSQL..."
    if [ ! -f /var/lib/postgresql/data/PG_VERSION ]; then
        su -s /bin/sh postgres -c "initdb -D /var/lib/postgresql/data"
    fi

    log "Enabling PostgreSQL..."
    rc-update add postgresql default
    rc-service postgresql start
    ok "PostgreSQL started"

    log "Running DB setup..."
    if [ -f /etc/monero/deploy.env ]; then
        source /etc/monero/deploy.env
        bash /opt/monero-scripts/setup_db.sh
        ok "Database initialised"
    else
        log "WARNING: /etc/monero/deploy.env not found. Run setup_db.sh manually."
    fi

    log "Applying PostgreSQL performance config..."
    cp /opt/monero-scripts/postgresql_monero.conf /var/lib/postgresql/data/conf.d/monero.conf 2>/dev/null || \
    cp /opt/monero-scripts/postgresql_monero.conf /etc/postgresql/monero.conf
    rc-service postgresql reload
    ok "PostgreSQL configured"
fi

echo ""
echo "════════════════════════════════════════════════════════"
echo "  Bootstrap complete for $VM_ROLE (Alpine Linux/OpenRC)"
echo "  Next: copy deploy.env.template → /etc/monero/deploy.env"
echo "        and fill in real values."
echo "════════════════════════════════════════════════════════"
