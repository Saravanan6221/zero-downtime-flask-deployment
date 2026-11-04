import os
from flask import Flask, jsonify

app = Flask(__name__)
APP_VERSION = "1.0.0"

@app.get("/")
def home():
    return jsonify(application="Zero Downtime Flask Demo", version=APP_VERSION, message="Version 1 is running")

@app.get("/health")
def health():
    if os.getenv("FAIL_HEALTH_CHECK", "false").lower() == "true":
        return jsonify(status="unhealthy", version=APP_VERSION), 500
    return jsonify(status="healthy", version=APP_VERSION), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
