from flask import Flask, render_template
import requests

app = Flask(__name__)

@app.route('/')
def index():
    # Отримуємо курси валют з НБУ
    rates_response = requests.get('http://192.168.56.102:8080/rates')
    rates = rates_response.json()

    # Отримуємо крипто курси
    crypto_response = requests.get('http://192.168.56.102:8080/crypto')
    crypto = crypto_response.json()

    # Об'єднуємо в один список
    all_rates = rates + crypto

    return render_template('index.html', rates=all_rates)

@app.route('/history')
def history():
    response = requests.get('http://192.168.56.103:5001/history')
    records = response.json()
    return render_template('history.html', records=records)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)