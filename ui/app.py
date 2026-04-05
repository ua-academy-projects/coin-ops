import os
import requests
from flask import Flask, render_template, request

app = Flask(__name__)

API_PROXY_URL = os.environ.get("API_PROXY_URL", "http://localhost:8000")


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

    return render_template("index.html", rates=rates, error=error, cc=cc)


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5000))
    app.run(host="0.0.0.0", port=port)
