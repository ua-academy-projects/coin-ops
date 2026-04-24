#!/bin/sh
set -eu

cd /repo

echo "==> Loading history schema..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f history/schema.sql

echo "==> Loading runtime bootstrap..."
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f runtime/00_run_all.sql