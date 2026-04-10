from flask import Flask, jsonify
from flask_cors import CORS
import requests
import pika
import redis
import json

app = Flask(__name__)
CORS(app)  # Allow browser requests from different origins

# RabbitMQ connection settings
RABBITMQ_HOST = "rabbitmq"
RABBITMQ_USER = "proxy_user"
RABBITMQ_PASS = "proxy_password"

# Cache will expire after 25 seconds
CACHE_TTL = 25

# Connect to local Redis instance
r = redis.Redis(host="redis", port=6379, db=0)

def send_to_queue(data):
    """Publish fetched rates to RabbitMQ so history service can consume them"""
    try:
        credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASS)
        connection = pika.BlockingConnection(
            pika.ConnectionParameters(host=RABBITMQ_HOST, credentials=credentials)
        )
        channel = connection.channel()
        channel.queue_declare(queue="rates")  # Create queue if it doesn't exist
        channel.basic_publish(exchange="", routing_key="rates", body=str(data))
        connection.close()
    except Exception as e:
        print(f"RabbitMQ error: {e}")

@app.route("/rates", methods=["GET"])
def get_rates():
    # Check Redis first — if fresh data exists, return it without calling APIs
    cached = r.get("rates_cache")
    if cached:
        print("Serving from Redis cache")
        return jsonify(json.loads(cached))

    # No cache — fetch fresh data from external APIs
    try:
        crypto = requests.get(
            "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=usd,uah",
            timeout=5
        ).json()
        currency = requests.get(
            "https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?json",
            timeout=5
        ).json()
        data = {"crypto": crypto, "currency": currency}

        # Store in Redis — auto-expires after CACHE_TTL seconds
        r.setex("rates_cache", CACHE_TTL, json.dumps(data))

        # Send to queue for history service to store
        send_to_queue(data)
        return jsonify(data)

    except Exception as e:
        # API failed — try returning stale cache rather than an error
        stale = r.get("rates_cache")
        if stale:
            print(f"Fetch failed, serving stale cache: {e}")
            return jsonify(json.loads(stale))
        return jsonify({"error": str(e)}), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
