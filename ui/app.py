import os
from collections import defaultdict
from datetime import datetime

import requests
from flask import Flask, make_response, render_template, request

app = Flask(__name__)


@app.template_filter("pretty_date")
def pretty_date_filter(value):
    """Format a date string into '08 Apr 2026'."""
    if not value:
        return value
    for fmt in ("%d.%m.%Y", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            dt = datetime.strptime(str(value)[:19], fmt)
            return dt.strftime("%d %b %Y")
        except ValueError:
            continue
    return value


@app.template_filter("pretty_datetime")
def pretty_datetime_filter(value):
    """Format a datetime string into '08 Apr 2026, 14:30'."""
    if not value:
        return value
    for fmt in ("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S"):
        try:
            dt = datetime.strptime(str(value)[:19], fmt)
            return dt.strftime("%d %b %Y, %H:%M")
        except ValueError:
            continue
    return value

API_PROXY_URL = os.environ.get("API_PROXY_URL", "http://localhost:8000")
HISTORY_SERVICE_URL = os.environ.get("HISTORY_SERVICE_URL", "http://localhost:8001")

CURRENCIES = ["USD", "EUR", "GBP", "PLN", "CHF", "JPY", "CNY", "CAD"]


@app.route("/")
def index():
    cc = request.args.get("cc", "")
    rates = []
    error = None

    url = f"{API_PROXY_URL}/rates"
    if cc:
        url += f"?cc={cc.upper()}"

    try:
        resp = requests.get(url, timeout=5)
        resp.raise_for_status()
        rates = resp.json()
    except requests.exceptions.ConnectionError:
        error = "Could not connect to the API proxy."
    except requests.exceptions.HTTPError as e:
        error = f"API proxy returned an error: {e}"
    except Exception as e:
        error = str(e)

    prev_rates = {}
    if rates:
        cc_param = cc if cc else ",".join(r["code"] for r in rates)
        current_date = rates[0].get("date", "")
        try:
            hist_resp = requests.get(
                f"{HISTORY_SERVICE_URL}/history",
                params={"cc": cc_param, "range": "7d", "limit": 500},
                timeout=3,
            )
            if hist_resp.ok:
                by_code = defaultdict(list)
                for rec in hist_resp.json():
                    by_code[rec["code"]].append(rec)
                for code, recs in by_code.items():
                    recs.sort(key=lambda r: r["rate_date"], reverse=True)
                    prev = next((r for r in recs if r["rate_date"] != current_date), None)
                    if prev:
                        curr = next((r["rate"] for r in rates if r["code"] == code), None)
                        if curr is not None:
                            delta = curr - prev["rate"]
                            pct = (delta / prev["rate"] * 100) if prev["rate"] else 0
                            prev_rates[code] = {"rate": prev["rate"], "delta": delta, "pct": pct}
        except Exception:
            pass

    favorites = {c for c in request.cookies.get("favorites", "").split(",") if c}

    return render_template("index.html", rates=rates, error=error, cc=cc, view="rates",
                           currencies=CURRENCIES, prev_rates=prev_rates, favorites=favorites)


@app.route("/history")
def history():
    if not request.args:
        saved_cc = request.cookies.get("history_cc", "")
        selected = [c for c in saved_cc.split(",") if c] or ["USD"]
        time_range = request.cookies.get("history_range", "7d")
    else:
        selected = request.args.getlist("cc") or ["USD"]
        time_range = request.args.get("range", "7d")

    records = []
    error = None

    url = f"{HISTORY_SERVICE_URL}/history?cc={','.join(c.upper() for c in selected)}&range={time_range}"
    try:
        resp = requests.get(url, timeout=5)
        resp.raise_for_status()
        records = resp.json()
    except requests.exceptions.ConnectionError:
        error = "Could not connect to the history service."
    except requests.exceptions.HTTPError as e:
        error = f"History service returned an error: {e}"
    except Exception as e:
        error = str(e)

    rendered = render_template("index.html", records=records, error=error,
                               selected=selected, time_range=time_range,
                               view="history", currencies=CURRENCIES)
    resp = make_response(rendered)
    resp.set_cookie("history_cc", ",".join(selected), max_age=31536000, samesite="Lax")
    resp.set_cookie("history_range", time_range, max_age=31536000, samesite="Lax")
    return resp


def build_chart_data(records):
    by_code = defaultdict(dict)
    all_dates = set()

    for r in records:
        raw = r.get("rate_date", "")
        try:
            dt = datetime.strptime(raw, "%d.%m.%Y")
        except ValueError:
            continue
        date_key = dt.strftime("%Y-%m-%d")
        by_code[r["code"]][date_key] = r["rate"]
        all_dates.add(date_key)

    sorted_dates = sorted(all_dates)
    labels = [datetime.strptime(d, "%Y-%m-%d").strftime("%d %b") for d in sorted_dates]

    datasets = []
    for code in sorted(by_code.keys()):
        rates = [by_code[code].get(d) for d in sorted_dates]
        datasets.append({"code": code, "rates": rates})

    return {"labels": labels, "datasets": datasets}


@app.route("/charts")
def charts():
    if not request.args:
        saved_cc = request.cookies.get("charts_cc", "")
        selected = [c for c in saved_cc.split(",") if c] or ["USD"]
        time_range = request.cookies.get("charts_range", "30d")
        chart_mode = request.cookies.get("charts_mode", "absolute")
    else:
        selected = request.args.getlist("cc") or ["USD"]
        time_range = request.args.get("range", "30d")
        chart_mode = request.args.get("mode", "absolute")
    if chart_mode not in ("absolute", "normalized"):
        chart_mode = "absolute"

    chart_data = {"labels": [], "datasets": []}
    error = None

    url = f"{HISTORY_SERVICE_URL}/history?cc={','.join(c.upper() for c in selected)}&range={time_range}&limit=5000"
    try:
        resp = requests.get(url, timeout=5)
        resp.raise_for_status()
        records = resp.json()
        chart_data = build_chart_data(records)
    except requests.exceptions.ConnectionError:
        error = "Could not connect to the history service."
    except requests.exceptions.HTTPError as e:
        error = f"History service returned an error: {e}"
    except Exception as e:
        error = str(e)

    rendered = render_template("index.html", chart_data=chart_data, error=error,
                               selected=selected, time_range=time_range,
                               chart_mode=chart_mode, view="charts", currencies=CURRENCIES)
    resp = make_response(rendered)
    resp.set_cookie("charts_cc", ",".join(selected), max_age=31536000, samesite="Lax")
    resp.set_cookie("charts_range", time_range, max_age=31536000, samesite="Lax")
    resp.set_cookie("charts_mode", chart_mode, max_age=31536000, samesite="Lax")
    return resp


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
