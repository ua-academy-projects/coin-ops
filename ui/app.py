import os
from datetime import datetime

import requests
from flask import Flask, render_template, request

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

    return render_template("index.html", rates=rates, error=error, cc=cc, view="rates",
                           currencies=CURRENCIES)


@app.route("/history")
def history():
    selected = request.args.getlist("cc")  # multi-select: ?cc=USD&cc=EUR
    if not selected:
        selected = ["USD"]
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

    return render_template("index.html", records=records, error=error,
                           selected=selected, time_range=time_range,
                           view="history", currencies=CURRENCIES)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
