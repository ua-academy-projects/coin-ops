#!/usr/bin/env bash
# VM3 — PostgreSQL initial setup
# Run once as root after installing PostgreSQL

set -euo pipefail

DB_NAME="${DB_NAME:-monero_privacy}"
DB_USER="${DB_USER:-monero}"
DB_PASSWORD="${DB_PASSWORD:-changeme_in_production}"
SCHEMA_FILE="/opt/monero-privacy-system/database/schema.sql"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [VM3-SETUP] $*"; }

log "Creating database user..."
su -s /bin/sh postgres -c "psql -c \"CREATE USER $DB_USER WITH PASSWORD '$DB_PASSWORD';\"" 2>/dev/null || \
    log "User may already exist, skipping."

log "Creating database..."
su -s /bin/sh postgres -c "psql -c \"CREATE DATABASE $DB_NAME OWNER $DB_USER;\"" 2>/dev/null || \
    log "Database may already exist, skipping."

log "Granting privileges..."
su -s /bin/sh postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;\""

log "Applying schema..."
PGPASSWORD="$DB_PASSWORD" psql -h localhost -U "$DB_USER" -d "$DB_NAME" -f "$SCHEMA_FILE"

log "PostgreSQL setup complete."
log "Connection string: postgresql://$DB_USER:***@localhost:5432/$DB_NAME"
