import os
from flask import Flask, render_template, request, jsonify
import requests

app = Flask(__name__)

# URL'и до бекенд сервісів — читаються з env або дефолти для VM
PROXY_URL = os.getenv('PROXY_URL', 'http://192.168.56.102:8080')
CONSUMER_URL = os.getenv('CONSUMER_URL', 'http://192.168.56.103:5001')

@app.route('/')
def index():
    rates = []
    crypto = []
    favorites = []
    history = []

    try:
        rates = requests.get(f'{PROXY_URL}/rates', timeout=5).json()
    except Exception as e:
        print(f"Помилка НБУ: {e}")

    try:
        crypto = requests.get(f'{PROXY_URL}/crypto', timeout=5).json()
    except Exception as e:
        print(f"Помилка CoinGecko: {e}")

    try:
        favorites = requests.get(f'{CONSUMER_URL}/favorites', timeout=5).json()
    except Exception as e:
        print(f"Помилка favorites: {e}")

    try:
        history = requests.get(f'{CONSUMER_URL}/history?hours=24', timeout=10).json()
    except Exception as e:
        print(f"Помилка history: {e}")

    return render_template('index.html', rates=rates, crypto=crypto, favorites=favorites, history=history)

@app.route('/api/favorites', methods=['POST'])
def save_favorites():
    try:
        data = request.get_json()
        response = requests.post(
            f'{CONSUMER_URL}/favorites',
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
            f'{CONSUMER_URL}/history?hours={hours}',
            timeout=10
        )
        records = response.json()
    except Exception as e:
        print(f"Помилка history: {e}")

    try:
        favorites = requests.get(f'{CONSUMER_URL}/favorites', timeout=5).json()
    except Exception as e:
        print(f"Помилка favorites: {e}")

    return render_template('history.html', records=records, current_hours=hours, favorites=favorites)

if __name__ == '__main__':
    port = int(os.getenv('PORT', '5000'))
    debug = os.getenv('DEBUG', 'false').lower() == 'true'
    app.run(host='0.0.0.0', port=port, debug=debug)