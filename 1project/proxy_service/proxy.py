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


def get_btc_price():
    url = "https://api.coinbase.com/v2/prices/BTC-USD/spot"
    r = requests.get(url, timeout=5)
    data = r.json()
    return float(data["data"]["amount"])


def send_to_queue(price):
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
            body=json.dumps({"price": price}),
            properties=pika.BasicProperties(delivery_mode=2)
        )
        connection.close()
        print(f"Sent to queue: {price}")
    except Exception as e:
        print(f"RabbitMQ error: {e}")


@app.route("/price")
def get_price():
    price = get_btc_price()
    send_to_queue(price)
    return jsonify({"price": price})


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5001, debug=True)