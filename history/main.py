#!/usr/bin/env python3
"""
history-api — FastAPI service exposing historical market data.
Runs as a systemd service (history-api.service) on node-01.
Shares the same venv as consumer.py; never writes to PostgreSQL.
"""
import os
import json
import yaml
import boto3
from typing import Optional

import psycopg2
import psycopg2.extras
import uvicorn
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

# Config setup
CONFIG_PATH = os.environ.get("CONFIG_PATH", "/opt/coinops/config.yaml")
CLOUD_PROVIDER = os.environ.get("CLOUD_PROVIDER", "aws") # aws or gcp

# AWS Config
AWS_SECRET_NAME = os.environ.get("AWS_SECRET_NAME", "coinops/production/app-secrets")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

# GCP Config
GCP_PROJECT_ID = os.environ.get("GCP_PROJECT_ID")
GCP_SECRET_ID = os.environ.get("GCP_SECRET_ID", "coinops-app-secrets")

def load_config() -> dict:
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, "r") as f:
            return yaml.safe_load(f)
    print(f"Warning: config file not found at {CONFIG_PATH}. Using fallback.")
    return {}

def fetch_secrets_aws() -> dict:
    session = boto3.session.Session()
    client = session.client(service_name='secretsmanager', region_name=AWS_REGION)
    response = client.get_secret_value(SecretId=AWS_SECRET_NAME)
    return json.loads(response['SecretString'])

def fetch_secrets_gcp() -> dict:
    from google.cloud import secretmanager
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{GCP_PROJECT_ID}/secrets/{GCP_SECRET_ID}/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return json.loads(response.payload.data.decode("UTF-8"))

def fetch_secrets() -> dict:
    try:
        if CLOUD_PROVIDER == "gcp":
            return fetch_secrets_gcp()
        return fetch_secrets_aws()
    except Exception as e:
        print(f"Warning: failed to fetch secrets from {CLOUD_PROVIDER.upper()} Secret Manager: {e}")
        return {}

config_data = load_config()
secrets_data = fetch_secrets()

# Fallback to local environment variables if secret manager fails or isn't configured
DATABASE_URL = secrets_data.get("DATABASE_URL") or os.environ.get("DATABASE_URL")

if not DATABASE_URL:
    raise RuntimeError("DATABASE_URL is required but not found in secrets or environment")

app = FastAPI(title="Coin-Ops History API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)


def get_db():
    return psycopg2.connect(
        DATABASE_URL,
        cursor_factory=psycopg2.extras.RealDictCursor,
    )


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/history")
def get_history(
    limit: int = Query(default=50, ge=1, le=200),
    category: Optional[str] = Query(default=None),
):
    """Return the most recent market snapshots across all markets."""
    conn = get_db()
    try:
        with conn.cursor() as cur:
            if category:
                cur.execute(
                    """
                    SELECT id, fetched_at, question, slug,
                           yes_price, no_price, volume_24h, category, end_date
                    FROM market_snapshots
                    WHERE category ILIKE %s
                    ORDER BY fetched_at DESC
                    LIMIT %s
                    """,
                    (f"%{category}%", limit),
                )
            else:
                cur.execute(
                    """
                    SELECT id, fetched_at, question, slug,
                           yes_price, no_price, volume_24h, category, end_date
                    FROM market_snapshots
                    ORDER BY fetched_at DESC
                    LIMIT %s
                    """,
                    (limit,),
                )
            rows = cur.fetchall()
        return [dict(r) for r in rows]
    finally:
        conn.close()


@app.get("/history/{slug}")
def get_market_history(
    slug: str,
    limit: int = Query(default=100, ge=1, le=500),
):
    """Return time-series price history for a single market (by slug)."""
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT fetched_at, yes_price, no_price, volume_24h
                FROM market_snapshots
                WHERE slug = %s
                ORDER BY fetched_at DESC
                LIMIT %s
                """,
                (slug, limit),
            )
            rows = cur.fetchall()
        if not rows:
            raise HTTPException(status_code=404, detail="Market not found")
        return [dict(r) for r in rows]
    finally:
        conn.close()


@app.get("/prices/history/{coin}")
def get_price_history(
    coin: str,
    limit: int = Query(default=500, ge=1, le=2000),
):
    """Return time-series price history for a coin (bitcoin, ethereum, usd_uah)."""
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT fetched_at, coin, price_usd, change_24h
                FROM price_snapshots
                WHERE coin = %s
                ORDER BY fetched_at DESC
                LIMIT %s
                """,
                (coin, limit),
            )
            rows = cur.fetchall()
        if not rows:
            raise HTTPException(status_code=404, detail="No price data for this coin")
        return [dict(r) for r in rows]
    finally:
        conn.close()


if __name__ == "__main__":
    port_config = config_data.get("history", {}).get("port")
    port = int(port_config or os.environ.get("PORT", 8000))
    uvicorn.run(app, host="0.0.0.0", port=port)
