import json
import os
from datetime import datetime
from decimal import Decimal
from html import escape

from django.shortcuts import render
from redis import Redis
from redis.exceptions import RedisError

from .models import ExchangeRate


CACHE_TTL_SECONDS = int(os.getenv("REDIS_CACHE_TTL", "60"))


def get_redis_client():
    return Redis(
        host=os.getenv("REDIS_HOST", "127.0.0.1"),
        port=int(os.getenv("REDIS_PORT", "6379")),
        db=int(os.getenv("REDIS_DB", "0")),
        decode_responses=True,
        socket_timeout=2,
        socket_connect_timeout=2,
    )


def serialize_rates(rates):
    payload = []
    for item in rates:
        payload.append(
            {
                "cc": item.cc,
                "txt": item.txt,
                "rate": str(item.rate),
                "exchange_date": item.exchange_date.isoformat(),
                "collected_at": item.collected_at.isoformat(),
            }
        )
    return payload


def deserialize_rates(items):
    payload = []
    for item in items:
        payload.append(
            {
                "cc": item["cc"],
                "txt": item["txt"],
                "rate": Decimal(item["rate"]),
                "exchange_date": datetime.fromisoformat(item["exchange_date"]).date(),
                "collected_at": datetime.fromisoformat(item["collected_at"]),
            }
        )
    return payload


def build_sparkline(values):
    width = 120
    height = 36

    if not values:
        return ""

    if len(values) == 1:
        y = height / 2
        points = f"0,{y:.2f} {width},{y:.2f}"
    else:
        minimum = min(values)
        maximum = max(values)
        spread = maximum - minimum
        if spread == 0:
            spread = Decimal("1")

        points_list = []
        for index, value in enumerate(values):
            x = (width / (len(values) - 1)) * index
            ratio = float((value - minimum) / spread)
            y = height - (ratio * (height - 4)) - 2
            points_list.append(f"{x:.2f},{y:.2f}")
        points = " ".join(points_list)

    return (
        f'<svg viewBox="0 0 {width} {height}" width="{width}" height="{height}" '
        f'aria-hidden="true" focusable="false">'
        f'<polyline fill="none" stroke="#c44b2d" stroke-width="2.5" '
        f'stroke-linecap="round" stroke-linejoin="round" points="{escape(points)}" />'
        f"</svg>"
    )


def summarize_rates(rates):
    def value(item, key):
        if isinstance(item, dict):
            return item[key]
        return getattr(item, key)

    grouped = {}

    for item in sorted(rates, key=lambda row: (value(row, "cc"), value(row, "collected_at"))):
        currency = grouped.setdefault(
            value(item, "cc"),
            {
                "cc": value(item, "cc"),
                "txt": value(item, "txt"),
                "rate": value(item, "rate"),
                "exchange_date": value(item, "exchange_date"),
                "samples": [],
                "sample_count": 0,
                "sparkline": "",
            },
        )
        currency["rate"] = value(item, "rate")
        currency["exchange_date"] = value(item, "exchange_date")
        currency["samples"].append(value(item, "rate"))

    results = []
    for currency in grouped.values():
        currency["sample_count"] = len(currency["samples"])
        currency["sparkline"] = build_sparkline(currency["samples"])
        results.append(currency)

    return sorted(results, key=lambda item: item["cc"])


def load_rates_for_date(selected_date):
    cache_key = f"rates:{selected_date.isoformat()}"
    cache_hit = False

    try:
        redis_client = get_redis_client()
        cached = redis_client.get(cache_key)
        if cached:
            return deserialize_rates(json.loads(cached)), True
    except RedisError:
        pass

    rates = list(
        ExchangeRate.objects.filter(exchange_date=selected_date)
        .order_by("cc")
        .only("cc", "txt", "rate", "exchange_date", "collected_at")
    )

    try:
        redis_client = get_redis_client()
        redis_client.setex(cache_key, CACHE_TTL_SECONDS, json.dumps(serialize_rates(rates)))
    except RedisError:
        pass

    return rates, cache_hit


def index(request):
    selected_date = None
    selected_raw = request.GET.get("date", "").strip()

    if selected_raw:
        try:
            selected_date = datetime.strptime(selected_raw, "%Y-%m-%d").date()
        except ValueError:
            selected_date = None

    if selected_date is None:
        selected_date = (
            ExchangeRate.objects.order_by("-exchange_date")
            .values_list("exchange_date", flat=True)
            .first()
        )

    available_dates = list(
        ExchangeRate.objects.order_by("-exchange_date")
        .values_list("exchange_date", flat=True)
        .distinct()[:14]
    )

    rates = []
    summary_rows = []
    cache_hit = False
    if selected_date is not None:
        rates, cache_hit = load_rates_for_date(selected_date)
        summary_rows = summarize_rates(rates)

    context = {
        "rates": summary_rows,
        "selected_date": selected_date,
        "available_dates": available_dates,
        "cache_hit": cache_hit,
        "rate_count": len(summary_rows),
    }
    return render(request, "dashboard/index.html", context)
