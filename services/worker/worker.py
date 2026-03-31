#!/usr/bin/python3

"""
CoinOps ingestion worker (VM3).

Polls the Go proxy for normalized rates on a fixed interval and persists each
snapshot row into PostgreSQL on VM4. Designed so the HTTP pull can later be
replaced by a message-broker consumer without changing DB insert logic.
"""

from __future__ import annotations

import logging
import os
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Iterable, Mapping, MutableMapping, Optional
from urllib.parse import unquote, urlparse

import psycopg2
import requests
from psycopg2.extras import execute_values

LOG = logging.getLogger("coinops.worker")

# Default service addresses match the private Vagrant subnet described in the project brief.
_DEFAULT_PROXY = "http://10.10.1.3:8080"
_DEFAULT_PG_HOST = "10.10.1.5"
_DEFAULT_PG_PORT = "5432"
_DEFAULT_PG_USER = "coinops"
_DEFAULT_PG_DB = "coinops_db"


@dataclass(frozen=True)
class WorkerConfig:
    """Runtime configuration loaded from environment variables."""

    proxy_base_url: str
    rates_path: str
    pg_host: str
    pg_port: int
    pg_user: str
    pg_password: str
    pg_database: str
    poll_interval_seconds: int
    http_timeout_seconds: float

    @classmethod
    def from_environ(cls, environ: Optional[MutableMapping[str, str]] = None) -> "WorkerConfig":
        """
        Build config from ``os.environ``.

        ``DATABASE_URL`` overrides discrete ``PG*`` variables when set
        (``postgresql://user:pass@host:port/dbname``).
        """
        env = environ if environ is not None else os.environ
        proxy = env.get("PROXY_URL", _DEFAULT_PROXY).rstrip("/")
        rates_path = env.get("COINOPS_RATES_PATH", "/api/v1/rates")
        db_url = env.get("DATABASE_URL", "").strip()
        if db_url:
            host, port, user, password, database = _parse_database_url(db_url)
        else:
            host = env.get("PGHOST", _DEFAULT_PG_HOST)
            port = int(env.get("PGPORT", _DEFAULT_PG_PORT))
            user = env.get("PGUSER", _DEFAULT_PG_USER)
            password = env.get("PGPASSWORD", "")
            database = env.get("PGDATABASE", _DEFAULT_PG_DB)
        poll_sec = int(env.get("COINOPS_POLL_SECONDS", "300"))
        timeout = float(env.get("COINOPS_HTTP_TIMEOUT", "30"))
        if not password:
            raise ValueError("PGPASSWORD or DATABASE_URL with password is required")
        return cls(
            proxy_base_url=proxy,
            rates_path=rates_path if rates_path.startswith("/") else "/" + rates_path,
            pg_host=host,
            pg_port=port,
            pg_user=user,
            pg_password=password,
            pg_database=database,
            poll_interval_seconds=max(poll_sec, 60),
            http_timeout_seconds=timeout,
        )


def _parse_database_url(url: str) -> tuple[str, int, str, str, str]:
    """
    Parse a PostgreSQL URL into connection components.

    Expected form: ``postgresql://user:password@host:port/dbname`` (port optional).
    Userinfo is percent-decoded so passwords may contain reserved characters.
    """
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


def fetch_rates(cfg: WorkerConfig) -> tuple[list[dict[str, Any]], datetime, dict[str, str]]:
    """
    GET normalized rates from the proxy.

    Returns:
        Tuple of (rate dicts as returned by API, API ``fetched_at`` parsed to UTC, errors map).
        When the HTTP call fails, returns ``([], utc_now, {"http": "..."})``.
    """
    url = cfg.proxy_base_url + cfg.rates_path
    try:
        resp = requests.get(url, timeout=cfg.http_timeout_seconds)
        resp.raise_for_status()
    except requests.RequestException as exc:
        LOG.warning("proxy request failed: %s", exc)
        return [], datetime.now(timezone.utc), {"http": str(exc)}
    try:
        payload: Mapping[str, Any] = resp.json()
    except ValueError as exc:
        LOG.warning("invalid JSON from proxy: %s", exc)
        return [], datetime.now(timezone.utc), {"json": str(exc)}
    rates = payload.get("rates") or []
    if not isinstance(rates, list):
        LOG.warning("proxy payload missing list 'rates'")
        return [], datetime.now(timezone.utc), {"shape": "rates is not a list"}
    raw_errors = payload.get("errors") or {}
    errors = {str(k): str(v) for k, v in raw_errors.items()} if isinstance(raw_errors, dict) else {}
    fetched_raw = payload.get("fetched_at")
    fetched_at = _parse_fetched_at(fetched_raw)
    # Persist whatever rows we received; partial upstream errors still yield insertable rows.
    out: list[dict[str, Any]] = [r for r in rates if isinstance(r, dict)]
    return out, fetched_at, errors


def _parse_fetched_at(value: Any) -> datetime:
    """Parse RFC3339 ``fetched_at`` from the proxy; fall back to current UTC."""
    if not value or not isinstance(value, str):
        return datetime.now(timezone.utc)
    try:
        # fromisoformat handles most RFC3339 variants from Go's encoding/json
        if value.endswith("Z"):
            value = value[:-1] + "+00:00"
        dt = datetime.fromisoformat(value)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)
    except ValueError:
        return datetime.now(timezone.utc)


def insert_rates(
    conn: Any,
    rates: Iterable[Mapping[str, Any]],
    batch_time: datetime,
) -> int:
    """
    Insert one DB row per normalized rate object.

    ``batch_time`` is stored implicitly via ``created_at DEFAULT now()`` unless we
    want alignment with proxy time — we use server ``now()`` for ingestion time;
    the proxy's ``fetched_at`` is not a column in MVP schema, so all rows in a
    batch share ``created_at`` at insert time (same transaction).

    Args:
        conn: An open psycopg2 connection.
        rates: Iterable of dicts with keys matching proxy JSON.
        batch_time: Reserved for future use (e.g. explicit timestamp column).

    Returns:
        Number of rows inserted.
    """
    _ = batch_time  # MVP: schema uses DEFAULT now(); keep parameter for API stability.
    rows: list[tuple[Any, ...]] = []
    for item in rates:
        sym = str(item.get("asset_symbol", "")).strip()
        typ = str(item.get("asset_type", "")).strip()
        src = str(item.get("source", "")).strip()
        if not sym or typ not in ("fiat", "crypto") or not src:
            LOG.debug("skip invalid rate row: %s", item)
            continue
        puah = item.get("price_uah")
        pusd = item.get("price_usd")
        rows.append(
            (
                sym[:16],
                typ[:8],
                puah if puah is not None else None,
                pusd if pusd is not None else None,
                src[:32],
            )
        )
    if not rows:
        return 0
    sql = """
        INSERT INTO exchange_rates (asset_symbol, asset_type, price_uah, price_usd, source)
        VALUES %s
    """
    with conn.cursor() as cur:
        execute_values(cur, sql, rows, page_size=500)
    return len(rows)


def connect_pg(cfg: WorkerConfig) -> Any:
    """Open a PostgreSQL connection using worker configuration."""
    return psycopg2.connect(
        host=cfg.pg_host,
        port=cfg.pg_port,
        user=cfg.pg_user,
        password=cfg.pg_password,
        dbname=cfg.pg_database,
    )


def run_cycle(cfg: WorkerConfig) -> None:
    """Single poll: fetch from proxy, insert into DB, commit or rollback."""
    rates, fetched_at, errors = fetch_rates(cfg)
    if errors:
        LOG.info("proxy reported errors: %s", errors)
    if not rates:
        LOG.warning("no rates to insert (fetched_at=%s)", fetched_at.isoformat())
        return
    try:
        conn = connect_pg(cfg)
    except psycopg2.Error as exc:
        LOG.error("database connection failed: %s", exc)
        return
    try:
        inserted = insert_rates(conn, rates, fetched_at)
        conn.commit()
        LOG.info("inserted %d rows (proxy fetched_at=%s)", inserted, fetched_at.isoformat())
    except psycopg2.Error as exc:
        conn.rollback()
        LOG.error("insert failed: %s", exc)
    finally:
        conn.close()


def main() -> None:
    """Configure logging and run an infinite poll loop (sleep-based, exact interval in seconds)."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        stream=sys.stdout,
    )
    try:
        cfg = WorkerConfig.from_environ()
    except ValueError as exc:
        LOG.error("configuration error: %s", exc)
        sys.exit(1)

    LOG.info(
        "starting worker proxy=%s interval=%ss db=%s@%s:%s/%s",
        cfg.proxy_base_url + cfg.rates_path,
        cfg.poll_interval_seconds,
        cfg.pg_user,
        cfg.pg_host,
        cfg.pg_port,
        cfg.pg_database,
    )

    while True:
        run_cycle(cfg)
        time.sleep(cfg.poll_interval_seconds)


if __name__ == "__main__":
    main()
