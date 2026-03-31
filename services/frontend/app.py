#!/usr/bin/python3

"""
CoinOps Flask UI (VM1).

Serves a single page with two tabs: live rates from the Go proxy and the last 50
rows from PostgreSQL. Keeps HTTP and DB access in small functions so templates stay thin.
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from typing import Any, Optional, Sequence, Tuple
from urllib.parse import unquote, urlparse

import psycopg2
import requests
from flask import Flask, render_template

LOG = logging.getLogger("coinops.frontend")

_DEFAULT_PROXY = "http://10.10.1.3:8080"
_DEFAULT_PG_HOST = "10.10.1.5"
_DEFAULT_PG_PORT = "5432"
_DEFAULT_PG_USER = "coinops"
_DEFAULT_PG_DB = "coinops_db"


@dataclass(frozen=True)
class AppConfig:
    """Flask app configuration from the environment."""

    proxy_base_url: str
    rates_path: str
    pg_host: str
    pg_port: int
    pg_user: str
    pg_password: str
    pg_database: str
    http_timeout: float

    @classmethod
    def from_environ(cls) -> "AppConfig":
        proxy = os.environ.get("PROXY_URL", _DEFAULT_PROXY).rstrip("/")
        path = os.environ.get("COINOPS_RATES_PATH", "/api/v1/rates")
        if not path.startswith("/"):
            path = "/" + path
        db_url = os.environ.get("DATABASE_URL", "").strip()
        if db_url:
            host, port, user, password, database = _parse_database_url(db_url)
        else:
            host = os.environ.get("PGHOST", _DEFAULT_PG_HOST)
            port = int(os.environ.get("PGPORT", _DEFAULT_PG_PORT))
            user = os.environ.get("PGUSER", _DEFAULT_PG_USER)
            password = os.environ.get("PGPASSWORD", "")
            database = os.environ.get("PGDATABASE", _DEFAULT_PG_DB)
        timeout = float(os.environ.get("COINOPS_HTTP_TIMEOUT", "15"))
        return cls(
            proxy_base_url=proxy,
            rates_path=path,
            pg_host=host,
            pg_port=port,
            pg_user=user,
            pg_password=password,
            pg_database=database,
            http_timeout=timeout,
        )


def _parse_database_url(url: str) -> Tuple[str, int, str, str, str]:
    """Parse ``postgresql://`` / ``postgres://`` URLs (same rules as the worker)."""
    parsed = urlparse(url)
    if parsed.scheme not in ("postgresql", "postgres"):
        raise ValueError("DATABASE_URL scheme must be postgresql:// or postgres://")
    if not parsed.hostname:
        raise ValueError("DATABASE_URL must include a host")
    user = unquote(parsed.username or "")
    password = unquote(parsed.password or "")
    host = parsed.hostname
    port = int(parsed.port or 5432)
    database = (parsed.path or "").lstrip("/").split("?")[0]
    if not database:
        raise ValueError("DATABASE_URL must include a database name in the path")
    return host, port, user, password, database


def fetch_live_rates(cfg: AppConfig) -> Tuple[Optional[list], Optional[str], Optional[str]]:
    """
    Return (rates_list, fetched_at_iso, error_message).

    On success ``error_message`` is None; on transport/parse failure ``rates_list`` is None.
    """
    url = cfg.proxy_base_url + cfg.rates_path
    try:
        resp = requests.get(url, timeout=cfg.http_timeout)
        resp.raise_for_status()
        data = resp.json()
    except (requests.RequestException, ValueError) as exc:
        LOG.warning("live rates fetch failed: %s", exc)
        return None, None, str(exc)
    rates = data.get("rates")
    if not isinstance(rates, list):
        return None, None, "Invalid proxy payload: rates is not a list"
    fetched = data.get("fetched_at")
    fetched_s = str(fetched) if fetched is not None else None
    return rates, fetched_s, None


def fetch_history_rows(cfg: AppConfig, limit: int = 50) -> Tuple[Optional[Sequence[Tuple[Any, ...]]], Optional[str]]:
    """
    Load the last ``limit`` rows from ``exchange_rates`` (newest first).

    Returns (rows, error). Each row is
    (id, asset_symbol, asset_type, price_uah, price_usd, source, created_at).
    """
    if not cfg.pg_password:
        return None, "PGPASSWORD or DATABASE_URL with password is required"
    sql = """
        SELECT id, asset_symbol, asset_type, price_uah, price_usd, source, created_at
        FROM exchange_rates
        ORDER BY created_at DESC
        LIMIT %s
    """
    try:
        conn = psycopg2.connect(
            host=cfg.pg_host,
            port=cfg.pg_port,
            user=cfg.pg_user,
            password=cfg.pg_password,
            dbname=cfg.pg_database,
        )
    except psycopg2.Error as exc:
        LOG.warning("history DB connect failed: %s", exc)
        return None, str(exc)
    try:
        with conn.cursor() as cur:
            cur.execute(sql, (limit,))
            rows = cur.fetchall()
        return rows, None
    except psycopg2.Error as exc:
        return None, str(exc)
    finally:
        conn.close()


def create_app() -> Flask:
    """Application factory for tests and ``flask run``."""
    logging.basicConfig(level=logging.INFO)
    cfg = AppConfig.from_environ()
    app = Flask(__name__)
    app.config["COINOPS_CFG"] = cfg

    @app.route("/")
    def index() -> str:
        """Render the dashboard with current rates and recent history."""
        c: AppConfig = app.config["COINOPS_CFG"]
        live_rates, fetched_at, live_error = fetch_live_rates(c)
        history_rows, history_error = fetch_history_rows(c, limit=50)
        return render_template(
            "index.html",
            live_rates=live_rates,
            live_fetched_at=fetched_at,
            live_error=live_error,
            history_rows=history_rows or [],
            history_error=history_error,
        )

    return app


app = create_app()


if __name__ == "__main__":
    # Dev server; production on VM1 typically sits behind gunicorn/nginx.
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "5000")))
