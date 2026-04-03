import pika
import json
import psycopg2
import threading
import time
from flask import Flask, jsonify
from psycopg2.extras import RealDictCursor

app = Flask(__name__)

DB_CONFIG = {
    'host': 'localhost',
    'database': 'coinops',
    'user': 'coinops',
    'password': 'coinops123'
}

RABBITMQ_HOST = '192.168.56.104'

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
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute('SELECT * FROM rates ORDER BY created_at DESC LIMIT 500')
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify([dict(r) for r in rows])

if __name__ == '__main__':
    t = threading.Thread(target=consume)
    t.daemon = True
    t.start()
    app.run(host='0.0.0.0', port=5001, debug=False)