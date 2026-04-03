from flask import Flask, render_template
import requests

app = Flask(__name__)

@app.route('/')
def index():
    rates = []
    crypto = []

    try:
        rates = requests.get('http://192.168.56.102:8080/rates', timeout=5).json()
    except Exception as e:
        print(f"Помилка НБУ: {e}")

    try:
        crypto = requests.get('http://192.168.56.102:8080/crypto', timeout=5).json()
    except Exception as e:
        print(f"Помилка CoinGecko: {e}")

    return render_template('index.html', rates=rates, crypto=crypto)

@app.route('/history')
def history():
    response = requests.get('http://192.168.56.103:5001/history')
    records = response.json()
    return render_template('history.html', records=records)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)