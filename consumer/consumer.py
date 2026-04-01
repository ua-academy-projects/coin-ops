import pika
import json
import psycopg2
from flask import Flask, jsonify
from psycopg2.extras import RealDictCursor
import threading

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
    # Зберігаємо курси в PostgreSQL
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
    # Підключаємось до RabbitMQ
    credentials = pika.PlainCredentials('coinops', 'coinops123')
    connection = pika.BlockingConnection(
        pika.ConnectionParameters(
            host=RABBITMQ_HOST,
            credentials=credentials
        )
    )
    channel = connection.channel()

    # Створюємо чергу якщо не існує
    channel.queue_declare(queue='rates')

    def callback(ch, method, properties, body):
        # Отримали повідомлення з черги
        rates = json.loads(body)
        print(f"Отримано з черги: {rates}")
        save_rates(rates)

    # Слухаємо чергу
    channel.basic_consume(
        queue='rates',
        on_message_callback=callback,
        auto_ack=True
    )
    print("Чекаємо повідомлень з черги...")
    channel.start_consuming()

@app.route('/history', methods=['GET'])
def get_history():
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    cur.execute('SELECT * FROM rates ORDER BY created_at DESC LIMIT 100')
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify([dict(r) for r in rows])

if __name__ == '__main__':
    # Запускаємо consumer в окремому потоці
    # щоб Flask і RabbitMQ працювали одночасно
    t = threading.Thread(target=consume)
    t.daemon = True
    t.start()

    app.run(host='0.0.0.0', port=5001, debug=False)
