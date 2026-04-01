#!/usr/bin/python3

"""
CoinOps history service (VM3).

Responsibilities in Phase A:
1) Consume normalized snapshot events from RabbitMQ and persist rates to PostgreSQL.
2) Expose historical records over HTTP for the UI (`GET /api/v1/history`).
"""

from __future__ import annotations

import json
import logging
import os
import sys
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Iterable, Mapping, MutableMapping, Optional
from urllib.parse import unquote, urlparse

import pika
import psycopg2
from flask import Flask, jsonify, request
from psycopg2.extras import execute_values

LOG = logging.getLogger("coinops.history")

_DEFAULT_PG_HOST = "10.10.1.6"
_DEFAULT_PG_PORT = "5432"
_DEFAULT_PG_USER = "coinops"
_DEFAULT_PG_DB = "coinops_db"
_DEFAULT_MQ_URL = "amqp://coinops:coinops@10.10.1.5:5672/"
_DEFAULT_MQ_EXCHANGE = "coinops.rates"
_DEFAULT_MQ_QUEUE = "coinops.history"
_DEFAULT_MQ_ROUTING_KEY = "rates.snapshot"
_DEFAULT_HISTORY_LISTEN = "0.0.0.0"
_DEFAULT_HISTORY_PORT = "8090"


@dataclass(frozen=True)
class HistoryConfig:
    """Runtime configuration for MQ consumer + history API."""

    pg_host: str
    pg_port: int
    pg_user: str
    pg_password: str
    pg_database: str
    rabbitmq_url: str
    rabbitmq_exchange: str
    rabbitmq_queue: str
    rabbitmq_routing_key: str
    mq_consumer_enabled: bool
    http_api_enabled: bool
    history_listen: str
    history_port: int

    @classmethod
    def from_environ(cls, environ: Optional[MutableMapping[str, str]] = None) -> "HistoryConfig":
        """Load config from env vars; DATABASE_URL overrides PG* variables."""
        env = environ if environ is not None else os.environ
        db_url = env.get("DATABASE_URL", "").strip()
        if db_url:
            host, port, user, password, database = _parse_database_url(db_url)
        else:
            host = env.get("PGHOST", _DEFAULT_PG_HOST)
            port = int(env.get("PGPORT", _DEFAULT_PG_PORT))
            user = env.get("PGUSER", _DEFAULT_PG_USER)
            password = env.get("PGPASSWORD", "")
            database = env.get("PGDATABASE", _DEFAULT_PG_DB)
        if not password:
            raise ValueError("PGPASSWORD or DATABASE_URL with password is required")
        return cls(
            pg_host=host,
            pg_port=port,
            pg_user=user,
            pg_password=password,
            pg_database=database,
            rabbitmq_url=env.get("RABBITMQ_URL", _DEFAULT_MQ_URL),
            rabbitmq_exchange=env.get("RABBITMQ_EXCHANGE", _DEFAULT_MQ_EXCHANGE),
            rabbitmq_queue=env.get("RABBITMQ_QUEUE", _DEFAULT_MQ_QUEUE),
            rabbitmq_routing_key=env.get("RABBITMQ_ROUTING_KEY", _DEFAULT_MQ_ROUTING_KEY),
            mq_consumer_enabled=_env_bool(env.get("MQ_CONSUMER_ENABLED"), default=True),
            http_api_enabled=_env_bool(env.get("HTTP_API_ENABLED"), default=True),
            history_listen=env.get("HISTORY_LISTEN", _DEFAULT_HISTORY_LISTEN),
            history_port=int(env.get("HISTORY_PORT", _DEFAULT_HISTORY_PORT)),
        )


def _env_bool(value: Optional[str], default: bool) -> bool:
    """Parse bool-like env var values."""
    if value is None:
        return default
    return value.lower() in {"1", "true", "yes", "on"}


def _parse_database_url(url: str) -> tuple[str, int, str, str, str]:
    """Parse PostgreSQL DSN from postgresql://... URL."""
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
        raise ValueError("DATABASE_URL must include a database name in path")
    return host, port, user, password, database


def connect_pg(cfg: HistoryConfig) -> Any:
    """Open a PostgreSQL connection for inserts/selects."""
    return psycopg2.connect(
        host=cfg.pg_host,
        port=cfg.pg_port,
        user=cfg.pg_user,
        password=cfg.pg_password,
        dbname=cfg.pg_database,
    )


def insert_rates(conn: Any, rates: Iterable[Mapping[str, Any]]) -> int:
    """Insert one DB row per normalized rate object from MQ event."""
    rows: list[tuple[Any, ...]] = []
    for item in rates:
        sym = str(item.get("asset_symbol", "")).strip()
        typ = str(item.get("asset_type", "")).strip()
        src = str(item.get("source", "")).strip()
        if not sym or typ not in ("fiat", "crypto") or not src:
            continue
        rows.append(
            (
                sym[:16],
                typ[:8],
                item.get("price_uah"),
                item.get("price_usd"),
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


def _decode_event(body: bytes) -> list[dict[str, Any]]:
    """Extract normalized `rates` list from proxy MQ event payload."""
    payload: Mapping[str, Any] = json.loads(body.decode("utf-8"))
    data = payload.get("data")
    if not isinstance(data, dict):
        return []
    rates = data.get("rates")
    if not isinstance(rates, list):
        return []
    return [r for r in rates if isinstance(r, dict)]


def run_consumer_forever(cfg: HistoryConfig, stop_event: threading.Event) -> None:
    """
    Run RabbitMQ consumer loop with reconnects.

    Messages are ACKed only after successful DB commit.
    """
    while not stop_event.is_set():
        connection = None
        channel = None
        try:
            params = pika.URLParameters(cfg.rabbitmq_url)
            connection = pika.BlockingConnection(params)
            channel = connection.channel()
            channel.exchange_declare(exchange=cfg.rabbitmq_exchange, exchange_type="direct", durable=True)
            channel.queue_declare(queue=cfg.rabbitmq_queue, durable=True)
            channel.queue_bind(
                queue=cfg.rabbitmq_queue,
                exchange=cfg.rabbitmq_exchange,
                routing_key=cfg.rabbitmq_routing_key,
            )
            channel.basic_qos(prefetch_count=50)
            LOG.info(
                "history consumer connected exchange=%s queue=%s key=%s",
                cfg.rabbitmq_exchange,
                cfg.rabbitmq_queue,
                cfg.rabbitmq_routing_key,
            )
            while not stop_event.is_set():
                method, properties, body = channel.basic_get(queue=cfg.rabbitmq_queue, auto_ack=False)
                if method is None:
                    time.sleep(0.2)
                    continue
                try:
                    rates = _decode_event(body)
                    if not rates:
                        channel.basic_ack(method.delivery_tag)
                        continue
                    conn = connect_pg(cfg)
                    try:
                        inserted = insert_rates(conn, rates)
                        conn.commit()
                        LOG.info("history consumer inserted %d rows", inserted)
                    finally:
                        conn.close()
                    channel.basic_ack(method.delivery_tag)
                except Exception as exc:  # pylint: disable=broad-except
                    LOG.exception("consume/insert failed: %s", exc)
                    # Requeue to avoid data loss; in real setup add DLQ and retry limits.
                    channel.basic_nack(method.delivery_tag, requeue=True)
                _ = properties
        except Exception as exc:  # pylint: disable=broad-except
            LOG.warning("consumer reconnect after error: %s", exc)
            time.sleep(2)
        finally:
            try:
                if channel and channel.is_open:
                    channel.close()
            except Exception:  # pylint: disable=broad-except
                pass
            try:
                if connection and connection.is_open:
                    connection.close()
            except Exception:  # pylint: disable=broad-except
                pass


def fetch_history_rows(
    cfg: HistoryConfig,
    limit: int,
    asset_symbol: Optional[str],
    asset_type: Optional[str],
) -> list[dict[str, Any]]:
    """Read latest rows from DB with optional symbol/type filters."""
    clauses = []
    params: list[Any] = []
    if asset_symbol:
        clauses.append("asset_symbol = %s")
        params.append(asset_symbol.upper())
    if asset_type in {"fiat", "crypto"}:
        clauses.append("asset_type = %s")
        params.append(asset_type)

    where = ("WHERE " + " AND ".join(clauses)) if clauses else ""
    sql = f"""
        SELECT id, asset_symbol, asset_type, price_uah, price_usd, source, created_at
        FROM exchange_rates
        {where}
        ORDER BY created_at DESC
        LIMIT %s
    """
    params.append(limit)

    conn = connect_pg(cfg)
    try:
        with conn.cursor() as cur:
            cur.execute(sql, tuple(params))
            out = []
            for row in cur.fetchall():
                out.append(
                    {
                        "id": row[0],
                        "asset_symbol": row[1],
                        "asset_type": row[2],
                        "price_uah": float(row[3]) if row[3] is not None else None,
                        "price_usd": float(row[4]) if row[4] is not None else None,
                        "source": row[5],
                        "created_at": row[6].isoformat() if isinstance(row[6], datetime) else str(row[6]),
                    }
                )
            return out
    finally:
        conn.close()


def create_app(cfg: HistoryConfig) -> Flask:
    """Create HTTP API for historical data."""
    app = Flask(__name__)

    @app.get("/healthz")
    def healthz() -> Any:
        return {"status": "ok", "service": "history"}

    @app.get("/api/v1/history")
    def history() -> Any:
        try:
            limit = int(request.args.get("limit", "50"))
        except ValueError:
            limit = 50
        limit = max(1, min(limit, 500))
        symbol = request.args.get("asset_symbol")
        asset_type = request.args.get("asset_type")
        try:
            rows = fetch_history_rows(cfg, limit=limit, asset_symbol=symbol, asset_type=asset_type)
            return jsonify({"items": rows, "count": len(rows), "generated_at": datetime.now(timezone.utc).isoformat()})
        except Exception as exc:  # pylint: disable=broad-except
            LOG.exception("history query failed: %s", exc)
            return jsonify({"error": "history_query_failed", "detail": str(exc)}), 500

    return app


def main() -> None:
    """Boot consumer thread and/or HTTP API according to env flags."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        stream=sys.stdout,
    )
    try:
        cfg = HistoryConfig.from_environ()
    except ValueError as exc:
        LOG.error("configuration error: %s", exc)
        sys.exit(1)

    LOG.info(
        "history service db=%s@%s:%s/%s mq=%s http=%s:%s consumer=%s api=%s",
        cfg.pg_user,
        cfg.pg_host,
        cfg.pg_port,
        cfg.pg_database,
        cfg.rabbitmq_url,
        cfg.history_listen,
        cfg.history_port,
        cfg.mq_consumer_enabled,
        cfg.http_api_enabled,
    )

    stop_event = threading.Event()
    if cfg.mq_consumer_enabled:
        thread = threading.Thread(target=run_consumer_forever, args=(cfg, stop_event), daemon=True)
        thread.start()

    if cfg.http_api_enabled:
        app = create_app(cfg)
        app.run(host=cfg.history_listen, port=cfg.history_port)
        return

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        stop_event.set()


if __name__ == "__main__":
    main()
