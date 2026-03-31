from flask import Flask, render_template
import requests
import os

app = Flask(__name__)

PROXY_HOST   = os.environ.get("PROXY_HOST", "localhost")
HISTORY_HOST = os.environ.get("HISTORY_HOST", "localhost")


def get_current_price():
    try:
        r = requests.get(f"http://{PROXY_HOST}:5001/price", timeout=5)
        return r.json()["price"]
    except Exception as e:
        print(f"Proxy error: {e}")
        return None


@app.route("/")
def index():
    current_price = get_current_price()
    return render_template("index.html", current_price=current_price)


@app.route("/history")
def history():
    try:
        r = requests.get(f"http://{HISTORY_HOST}:5002/history", timeout=5)
        prices = r.json()["prices"]
    except Exception as e:
        print(f"History error: {e}")
        prices = []
    return render_template("history.html", prices=prices)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)  # 0 0 0 0 - ALL NETWORK INTERFACES LISTENING