#!/usr/bin/python3

"""
CoinOps history service (VM3).

Responsibilities:
1) Consume normalized snapshot events from RabbitMQ and persist rates to PostgreSQL.
2) Expose historical records over HTTP: GET /api/v1/history, GET /api/v1/history/series,
   GET /api/v1/history/dashboard.
"""

from __future__ import annotations

import logging
import sys
import threading
import time

from app import create_app
from config import HistoryConfig
from consumer import run_consumer_forever
from db import get_pg_pool, verify_db_schema

LOG = logging.getLogger("coinops.history")


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

    get_pg_pool(cfg)
    if cfg.mq_consumer_enabled:
        verify_db_schema(cfg)

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
        thread = threading.Thread(
            target=run_consumer_forever, args=(cfg, stop_event), daemon=True,
        )
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
