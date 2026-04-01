from flask import Flask, jsonify
import requests
import pika
import json
import os

app = Flask(__name__)

RABBITMQ_HOST  = os.environ.get("RABBITMQ_HOST", "localhost")   # finds environ var if not found - uses ip .14
RABBITMQ_USER  = os.environ.get("RABBITMQ_USER", "currency_app_user")
RABBITMQ_PASS  = os.environ.get("RABBITMQ_PASS", "password")
RABBITMQ_QUEUE = "currency_rates"

# set for performance, no duplicates for coins, good for for in
SUPPORTED_COINS = {"BTC", "ETH", "SOL", "BNB"}

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


# 1
@app.route("/price/<coin>")
def provide_price(coin):
    coin = coin.upper()
    if coin not in SUPPORTED_COINS:
        return jsonify({'error': "unsupported coin"}), 400
    price = fetch_price(coin)
    send_to_queue(coin,price)
    return jsonify({"price": price})



   
    send_to_queue(price)
    return jsonify({"price": price})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=True)