from flask import Flask, jsonify
import requests
import pika
import json
import os
import threading
import time

app = Flask(__name__)

RABBITMQ_HOST  = os.environ.get("RABBITMQ_HOST", "192.168.56.14")   # finds environ var if not found - uses ip .14
RABBITMQ_USER  = os.environ.get("RABBITMQ_USER", "currency_app_user")
RABBITMQ_PASS  = os.environ.get("RABBITMQ_PASS", "password")
RABBITMQ_QUEUE = "currency_rates"
HISTORY_HOST   = os.environ.get("HISTORY_HOST", "192.168.56.13")

# set for performance, no duplicates for coins, good for for in
SUPPORTED_COINS = {"BTC", "ETH", "SOL", "BNB"}
UPDATE_INTERVAL_SECONDS = 180
MAX_PRICE_STEP = {
    "BTC": 180.0,
    "ETH": 18.0,
    "SOL": 1.8,
    "BNB": 4.5,
}
last_sent_prices = {}

# default parameter coin="BTC"
def fetch_price(coin="BTC"):
    url = f"https://api.coinbase.com/v2/prices/{coin}-USD/spot"
    r = requests.get(url, timeout=5)
    data = r.json()
    print(data)
    return float(data["data"]["amount"])


def send_to_queue(coin,price):
    try:
        credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASS)
        params = pika.ConnectionParameters(
            host=RABBITMQ_HOST,
            credentials=credentials
        )
        connection = pika.BlockingConnection(params)
        channel = connection.channel()
        channel.queue_declare(queue=RABBITMQ_QUEUE, durable=True)
        channel.basic_publish(
            exchange="",
            routing_key=RABBITMQ_QUEUE,
            body=json.dumps({"coin": coin, "price": price}),
            properties=pika.BasicProperties(delivery_mode=2)    # message will be stored on a disk and survive Rabbitmq restarts
        )
        connection.close()
        print(f"Sent to queue: {coin} = {price}")
    except Exception as e:
        print(f"RabbitMQ error: {e}")


def get_latest_history_price(coin):
    try:
        response = requests.get(
            f"http://{HISTORY_HOST}:5002/chart",
            params={"coin": coin, "range": "1H"},
            timeout=5,
        )
        data = response.json()
        current_price = data.get("current_price")
        if current_price is None:
            return None
        return float(current_price)
    except Exception as e:
        print(f"History sync error for {coin}: {e}")
        return None


def smooth_price(coin, fetched_price):
    reference_price = last_sent_prices.get(coin)
    if reference_price is None:
        reference_price = get_latest_history_price(coin)

    if reference_price is None:
        return round(fetched_price, 2)

    max_step = MAX_PRICE_STEP.get(coin, 1.0)
    delta = fetched_price - reference_price
    if abs(delta) <= max_step:
        return round(fetched_price, 2)

    if delta > 0:
        return round(reference_price + max_step, 2)
    return round(reference_price - max_step, 2)


def refresh_all_coins():
    for coin in sorted(SUPPORTED_COINS):
        try:
            fetched_price = fetch_price(coin)
            price = smooth_price(coin, fetched_price)
            send_to_queue(coin, price)
            last_sent_prices[coin] = price
        except Exception as e:
            print(f"Background refresh error for {coin}: {e}")


def background_updater():
    while True:
        refresh_all_coins()
        time.sleep(UPDATE_INTERVAL_SECONDS)


def should_start_background_worker():
    return not app.debug or os.environ.get("WERKZEUG_RUN_MAIN") == "true"


# 1
@app.route("/price/<coin>")
def provide_price(coin):
    coin = coin.upper()
    if coin not in SUPPORTED_COINS:
        return jsonify({'error': "unsupported coin"}), 400
    fetched_price = fetch_price(coin)
    price = smooth_price(coin, fetched_price)
    send_to_queue(coin,price)
    last_sent_prices[coin] = price
    return jsonify({"price": price})


if __name__ == "__main__":
    if should_start_background_worker():
        updater_thread = threading.Thread(target=background_updater, daemon=True)
        updater_thread.start()
    app.run(host="0.0.0.0", port=5001, debug=True)
