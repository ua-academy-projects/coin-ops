from flask import Flask, render_template, request
import requests
import os

app = Flask(__name__)

PROXY_HOST   = os.environ.get("PROXY_HOST", "localhost")
HISTORY_HOST = os.environ.get("HISTORY_HOST", "localhost")
COINS = {"BTC", "ETH", "SOL", "BNB"}



def get_current_price(coin="BTC"):
    try:
        r = requests.get(f"http://{PROXY_HOST}:5001/price/{coin}", timeout=5)
        return round(r.json()["price"], 2)
    except Exception as e:
        print(f"Proxy error: {e}")
        return None

def get_stats(coin="BTC"):
    try:
        r = requests.get(f"http://{HISTORY_HOST}:5002/stats?coin={coin}", timeout=5)
        return r.json()
    except Exception as e:
        print(f"Stats error: {e}")
        return {"highest_price": None, "lowest_price": None}



@app.route("/")
def index():
    # request.args = ?... (localhost:5000?coin=ETH)
    # get coin from query paramter, if not provided - set default to BTC and make it uppercase
    # when user enters / for the first time - coin is not provided - default to BTC, when user clicks on ETH - coin=ETH, when user clicks on SOL - coin=SOL
    coin = request.args.get("coin", "BTC").upper()

    # if coin is not in the list of supported coins - set it to default BTC
    if coin not in COINS:
        coin = "BTC"
    current_price = get_current_price(coin)
    stats = get_stats(coin)
    return render_template("index.html", 
    current_price=current_price,
    selected_coin=coin,
    coins=COINS,
    highest_price=stats["highest_price"],
    lowest_price=stats["lowest_price"]
)


@app.route("/history")
def history():
    try:
        r = requests.get(f"http://{HISTORY_HOST}:5002/history", timeout=5)
        data = r.json()["data"]
    except Exception as e:
        print(f"History error: {e}")
        data = []
    return render_template("history.html", data=data)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)  # 0 0 0 0 - ALL NETWORK INTERFACES LISTENING