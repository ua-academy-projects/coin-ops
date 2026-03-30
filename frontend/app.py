from flask import Flask, render_template
import requests

app = Flask(__name__)

@app.route('/')
def index():
    response = requests.get('http://localhost:8080/rates')
    rates = response.json()
    
    
    return render_template('index.html', rates=rates)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
