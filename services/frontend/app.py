#!/usr/bin/python3

"""
CoinOps Flask UI (VM1).

Serves a single page with two tabs:
- live rates from the Go proxy
- historical analytics via the History Service API (no direct DB access)
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any, Optional, Tuple

import requests
from flask import Flask, jsonify, render_template, request

LOG = logging.getLogger("coinops.frontend")

_DEFAULT_PROXY = "http://10.10.1.3:8080"
_DEFAULT_HISTORY_API = "http://10.10.1.4:8090/api/v1/history"


def history_base_url_from_environ() -> str:
    """
    Base URL of the History Service (scheme + host[:port]), without path.

    Supports either:
    - HISTORY_BASE_URL=http://10.10.1.4:8090
    - HISTORY_API_URL=http://10.10.1.4:8090/api/v1/history (legacy full path — suffix stripped)
    """
    explicit = os.environ.get("HISTORY_BASE_URL", "").strip()
    if explicit:
        return explicit.rstrip("/")
    raw = os.environ.get("HISTORY_API_URL", _DEFAULT_HISTORY_API).strip().rstrip("/")
    for suffix in ("/api/v1/history", "/v1/history"):
        if raw.endswith(suffix):
            return raw[: -len(suffix)].rstrip("/")
    return raw


@dataclass(frozen=True)
class AppConfig:
    """Flask app configuration from the environment."""

    proxy_base_url: str
    rates_path: str
    history_base_url: str
    http_timeout: float

    @property
    def history_list_url(self) -> str:
        return f"{self.history_base_url}/api/v1/history"

    @property
    def history_series_url(self) -> str:
        return f"{self.history_base_url}/api/v1/history/series"

    @property
    def history_dashboard_url(self) -> str:
        return f"{self.history_base_url}/api/v1/history/dashboard"

    @classmethod
    def from_environ(cls) -> "AppConfig":
        proxy = os.environ.get("PROXY_URL", _DEFAULT_PROXY).rstrip("/")
        path = os.environ.get("COINOPS_RATES_PATH", "/api/v1/rates")
        if not path.startswith("/"):
            path = "/" + path
        base = history_base_url_from_environ()
        timeout = float(os.environ.get("COINOPS_HTTP_TIMEOUT", "15"))
        return cls(
            proxy_base_url=proxy,
            rates_path=path,
            history_base_url=base,
            http_timeout=timeout,
        )


def enrich_rates_with_crypto_uah(rates: list) -> None:
    """
    For crypto rows, set ``price_uah`` = ``price_usd * uah_per_usd`` where
    ``uah_per_usd`` is the official UAH price of USD (NBU) from the USD fiat row.

    Mutates rate dicts in place. Round to 2 decimals.
    """
    uah_per_usd: Optional[float] = None
    for item in rates:
        if not isinstance(item, dict):
            continue
        if str(item.get("asset_type", "")).lower() != "fiat":
            continue
        if str(item.get("asset_symbol", "")).upper() != "USD":
            continue
        pu = item.get("price_uah")
        if pu is None:
            continue
        try:
            uah_per_usd = float(pu)
        except (TypeError, ValueError):
            pass
        break
    if uah_per_usd is None or uah_per_usd <= 0:
        return
    for item in rates:
        if not isinstance(item, dict):
            continue
        if str(item.get("asset_type", "")).lower() != "crypto":
            continue
        pusd = item.get("price_usd")
        if pusd is None:
            continue
        try:
            item["price_uah"] = round(float(pusd) * uah_per_usd, 2)
        except (TypeError, ValueError):
            pass


def normalize_utc_iso_string(value: Any) -> Optional[str]:
    """
    Parse an ISO-like timestamp from the proxy or APIs and return UTC ISO-8601 with Z.

    Ensures the browser always receives an unambiguous instant (avoids mixing naive local
    vs Z/+00:00 parsing between tabs).
    """
    if value is None:
        return None
    if isinstance(value, datetime):
        dt = value
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        else:
            dt = dt.astimezone(timezone.utc)
        return dt.strftime("%Y-%m-%dT%H:%M:%S") + "Z"
    s = str(value).strip()
    if not s or s.lower() in ("none", "null"):
        return None
    try:
        if len(s) >= 11 and s[10] == " ":
            s = s[:10] + "T" + s[11:]
        if s.endswith("Z") or s.endswith("z"):
            s = s[:-1] + "+00:00"
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        else:
            dt = dt.astimezone(timezone.utc)
        return dt.strftime("%Y-%m-%dT%H:%M:%S") + "Z"
    except (ValueError, TypeError, OSError):
        return s


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
    enrich_rates_with_crypto_uah(rates)
    fetched = data.get("fetched_at")
    fetched_s = normalize_utc_iso_string(fetched) if fetched is not None else None
    return rates, fetched_s, None


def create_app() -> Flask:
    """Application factory for tests and ``flask run``."""
    logging.basicConfig(level=logging.INFO)
    cfg = AppConfig.from_environ()
    app = Flask(__name__)
    app.config["COINOPS_CFG"] = cfg

    @app.route("/")
    def index() -> str:
        """Render the dashboard with current rates."""
        c: AppConfig = app.config["COINOPS_CFG"]
        live_rates, fetched_at, live_error = fetch_live_rates(c)
        return render_template(
            "index.html",
            live_rates=live_rates,
            live_fetched_at=fetched_at,
            live_error=live_error,
        )

    @app.route("/api/live")
    def api_live():
        """Same-origin JSON for current rates (refresh without full page reload)."""
        c: AppConfig = app.config["COINOPS_CFG"]
        rates, fetched_at, err = fetch_live_rates(c)
        if err:
            return jsonify({"error": err, "rates": [], "fetched_at": None}), 502
        return jsonify({"rates": rates or [], "fetched_at": fetched_at})

    @app.route("/api/history")
    def api_history_proxy():
        """Same-origin proxy to History Service (avoids CORS for client-side refetch)."""
        c: AppConfig = app.config["COINOPS_CFG"]
        limit = request.args.get("limit", default=50, type=int)
        if limit is None or limit < 1:
            limit = 50
        limit = min(limit, 500)
        params: dict[str, Any] = {"limit": limit}
        sym = request.args.get("asset_symbol")
        typ = request.args.get("asset_type")
        if sym:
            params["asset_symbol"] = sym
        if typ in ("fiat", "crypto"):
            params["asset_type"] = typ
        try:
            resp = requests.get(c.history_list_url, params=params, timeout=c.http_timeout)
            resp.raise_for_status()
            return jsonify(resp.json())
        except (requests.RequestException, ValueError) as exc:
            LOG.warning("history proxy failed: %s", exc)
            return jsonify({"error": str(exc), "items": [], "count": 0}), 502

    @app.route("/api/history/series")
    def api_history_series_proxy():
        c: AppConfig = app.config["COINOPS_CFG"]
        params = dict(request.args)
        try:
            resp = requests.get(c.history_series_url, params=params, timeout=c.http_timeout)
            resp.raise_for_status()
            return jsonify(resp.json())
        except (requests.RequestException, ValueError) as exc:
            LOG.warning("history series proxy failed: %s", exc)
            return jsonify({"error": str(exc), "items": [], "count": 0}), 502

    @app.route("/api/history/dashboard")
    def api_history_dashboard_proxy():
        c: AppConfig = app.config["COINOPS_CFG"]
        params = dict(request.args)
        try:
            resp = requests.get(c.history_dashboard_url, params=params, timeout=c.http_timeout)
            resp.raise_for_status()
            return jsonify(resp.json())
        except (requests.RequestException, ValueError) as exc:
            LOG.warning("history dashboard proxy failed: %s", exc)
            return jsonify({"error": str(exc), "items": [], "count": 0}), 502

    return app


app = create_app()


if __name__ == "__main__":
    # Dev server; production on VM1 typically sits behind gunicorn/nginx.
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "5000")))
