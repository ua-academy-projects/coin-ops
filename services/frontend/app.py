#!/usr/bin/python3

"""
CoinOps Flask UI (VM1).

Serves a single page with two tabs:
- live rates from the Go proxy
- historical rates from the History Service API
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from typing import Optional, Tuple

import requests
from flask import Flask, render_template

LOG = logging.getLogger("coinops.frontend")

_DEFAULT_PROXY = "http://10.10.1.3:8080"
_DEFAULT_HISTORY_API = "http://10.10.1.4:8090/api/v1/history"


@dataclass(frozen=True)
class AppConfig:
    """Flask app configuration from the environment."""

    proxy_base_url: str
    rates_path: str
    history_api_url: str
    http_timeout: float

    @classmethod
    def from_environ(cls) -> "AppConfig":
        proxy = os.environ.get("PROXY_URL", _DEFAULT_PROXY).rstrip("/")
        path = os.environ.get("COINOPS_RATES_PATH", "/api/v1/rates")
        if not path.startswith("/"):
            path = "/" + path
        history_api_url = os.environ.get("HISTORY_API_URL", _DEFAULT_HISTORY_API)
        timeout = float(os.environ.get("COINOPS_HTTP_TIMEOUT", "15"))
        return cls(
            proxy_base_url=proxy,
            rates_path=path,
            history_api_url=history_api_url,
            http_timeout=timeout,
        )

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


def fetch_history_rows(cfg: AppConfig, limit: int = 50) -> Tuple[Optional[list], Optional[str]]:
    """Load latest history rows from the History Service API."""
    url = cfg.history_api_url
    try:
        resp = requests.get(url, params={"limit": limit}, timeout=cfg.http_timeout)
        resp.raise_for_status()
        payload = resp.json()
        items = payload.get("items")
        if not isinstance(items, list):
            return None, "Invalid history payload: items is not a list"
        return items, None
    except (requests.RequestException, ValueError) as exc:
        LOG.warning("history API request failed: %s", exc)
        return None, str(exc)


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
