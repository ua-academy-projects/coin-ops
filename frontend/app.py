from flask import Flask, render_template, request, jsonify
import requests

app = Flask(__name__)

@app.route('/')
def index():
    rates = []
    crypto = []
    favorites = []

    try:
        rates = requests.get('http://192.168.56.102:8080/rates', timeout=5).json()
    except Exception as e:
        print(f"Помилка НБУ: {e}")

    try:
        crypto = requests.get('http://192.168.56.102:8080/crypto', timeout=5).json()
    except Exception as e:
        print(f"Помилка CoinGecko: {e}")

    # Читаємо улюблені валюти з Redis (через consumer)
    try:
        favorites = requests.get('http://192.168.56.103:5001/favorites', timeout=5).json()
    except Exception as e:
        print(f"Помилка favorites: {e}")

    return render_template('index.html', rates=rates, crypto=crypto, favorites=favorites)

# Цей маршрут приймає запити від JavaScript і пересилає в consumer
@app.route('/api/favorites', methods=['POST'])
def save_favorites():
    try:
        data = request.get_json()
        response = requests.post(
            'http://192.168.56.103:5001/favorites',
            json=data,
            timeout=5
        )
        return jsonify(response.json())
    except Exception as e:
        print(f"Помилка збереження: {e}")
        return jsonify({'status': 'error'}), 500

@app.route('/history')
def history():
    hours = request.args.get('hours', 24, type=int)
    records = []
    favorites = []

    try:
        response = requests.get(
            f'http://192.168.56.103:5001/history?hours={hours}',
            timeout=10
        )
        records = response.json()
    except Exception as e:
        print(f"Помилка history: {e}")

    try:
        favorites = requests.get('http://192.168.56.103:5001/favorites', timeout=5).json()
    except Exception as e:
        print(f"Помилка favorites: {e}")

    return render_template('history.html', records=records, current_hours=hours, favorites=favorites)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)