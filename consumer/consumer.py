import pika
import json
import psycopg2
import threading
import time
import redis
from flask import Flask, jsonify, request
from psycopg2.extras import RealDictCursor

app = Flask(__name__)

DB_CONFIG = {
    'host': 'localhost',
    'database': 'coinops',
    'user': 'coinops',
    'password': 'coinops123'
}

RABBITMQ_HOST = '192.168.56.104'
redis_client = redis.Redis(host='localhost', port=6379, decode_responses=True)

def get_db():
    return psycopg2.connect(**DB_CONFIG)

def save_rates(rates):
    conn = get_db()
    cur = conn.cursor()
    for rate in rates:
        cur.execute(
            'INSERT INTO rates (currency, name, rate) VALUES (%s, %s, %s)',
            (rate['cc'], rate['txt'], rate['rate'])
        )
    conn.commit()
    cur.close()
    conn.close()

def consume():
    # Retry логіка — якщо RabbitMQ недоступний,
    # чекаємо 5 секунд і пробуємо знову
    while True:
        try:
            credentials = pika.PlainCredentials('coinops', 'coinops123')
            connection = pika.BlockingConnection(
                pika.ConnectionParameters(
                    host=RABBITMQ_HOST,
                    credentials=credentials,
                    connection_attempts=3,
                    retry_delay=5
                )
            )
            channel = connection.channel()
            channel.queue_declare(queue='rates')

            def callback(ch, method, properties, body):
                rates = json.loads(body)
                print(f"Отримано з черги: {rates}")
                save_rates(rates)

            channel.basic_consume(
                queue='rates',
                on_message_callback=callback,
                auto_ack=True
            )
            print("Підключено до RabbitMQ, чекаємо повідомлень...")
            channel.start_consuming()

        except Exception as e:
            print(f"Помилка: {e}. Спробую знову через 5 секунд...")
            time.sleep(5)

@app.route('/history', methods=['GET'])
def get_history():
    from flask import request as freq
    hours = freq.args.get('hours', 24, type=int)
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)

    if hours > 0:
        cur.execute(
            "SELECT * FROM rates WHERE created_at >= NOW() - INTERVAL '1 hour' * %s ORDER BY created_at DESC LIMIT 5000",
            (hours,)
        )
    else:
        cur.execute('SELECT * FROM rates ORDER BY created_at DESC LIMIT 10000')

    rows = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify([dict(r) for r in rows])

@app.route('/favorites', methods=['GET'])
def get_favorites():
    # Читаємо список улюблених валют з Redis
    favorites = redis_client.smembers('favorites')
    return jsonify(list(favorites))

@app.route('/favorites', methods=['POST'])
def set_favorites():
    # Зберігаємо список улюблених валют в Redis
    data = request.get_json()
    codes = data.get('codes', [])
    # Очищаємо старий список і записуємо новий
    redis_client.delete('favorites')
    if codes:
        redis_client.sadd('favorites', *codes)
    return jsonify({'status': 'ok'})

if __name__ == '__main__':
    t = threading.Thread(target=consume)
    t.daemon = True
    t.start()
    app.run(host='0.0.0.0', port=5001, debug=False)
