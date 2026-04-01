from flask import Flask, jsonify
import psycopg2
from psycopg2.extras import RealDictCursor

app = Flask(__name__)


DB_CONFIG = {
    'host': 'localhost',
    'database': 'coinops',
    'user': 'coinops',
    'password': 'coinops123'
}

def get_db():
    return psycopg2.connect(**DB_CONFIG)

@app.route('/save', methods=['POST'])
def save_rates():
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
