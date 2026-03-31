from flask import Flask, render_template
import requests

app = Flask(__name__)

@app.route('/')
def index():
    # Стукаємо до Go проксі на VM2
    response = requests.get('http://192.168.56.102:8080/rates')
    rates = response.json()
    return render_template('index.html', rates=rates)

@app.route('/history')
def history():
    # Стукаємо до History Service на VM3
    response = requests.get('http://192.168.56.103:5001/history')
    records = response.json()
    return render_template('history.html', records=records)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
