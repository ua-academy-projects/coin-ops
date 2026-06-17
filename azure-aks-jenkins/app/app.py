from flask import Flask, jsonify
import os

app = Flask(__name__)


@app.get("/")
def index():
    return jsonify(
        {
            "app": os.getenv("APP_TITLE", "Azure AKS Jenkins Demo"),
            "environment": os.getenv("APP_ENV", "dev"),
            "status": "ok",
        }
    )

