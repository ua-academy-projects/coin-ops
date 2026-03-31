from flask import Flask, jsonify
import psycopg2
from psycopg2.extras import RealDictCursor

app = Flask(__name__)

# Налаштування підключення до PostgreSQL
DB_CONFIG = {
    'host': 'localhost',
    'database': 'coinops',
    'user': 'coinops',
    'password': 'coinops123'
}

def get_db():
    # Підключаємось до бази даних
    return psycopg2.connect(**DB_CONFIG)

@app.route('/save', methods=['POST'])
def save_rates():
    # Цей маршрут буде викликати VM2 проксі
    # щоб зберегти курси в БД
    from flask import request
    data = request.json
    
    conn = get_db()
    cur = conn.cursor()
    
    for rate in data:
        cur.execute(
            'INSERT INTO rates (currency, name, rate) VALUES (%s, %s, %s)',
            (rate['cc'], rate['txt'], rate['rate'])
        )
    
    conn.commit()
    cur.close()
    conn.close()
    
    return jsonify({'status': 'saved'})

@app.route('/history', methods=['GET'])
def get_history():
    # Цей маршрут буде викликати VM1 Flask
    # щоб отримати історичні дані для вкладки 2
    conn = get_db()
    cur = conn.cursor(cursor_factory=RealDictCursor)
    
    cur.execute(
        'SELECT * FROM rates ORDER BY created_at DESC LIMIT 100'
    )
    rows = cur.fetchall()
    
    cur.close()
    conn.close()
    
    return jsonify([dict(r) for r in rows])

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, debug=True)
