import os 
import json
import boto3
from flask import Flask, jsonify

app = Flask(__name__)

QUEUE_URL = os.environ.get('QUEUE_URL', '')
sqs = boto3.client('sqs')

@app.route('/health')
def health():
    return jsonify({"status": "ok"}), 200

@app.route("/")
def index():
    return jsonify({"service": "doc-processor-api",
                    "endpoints": ["health", "/queue-depth"]}),200

@app.route('/queue-depth')
def queue_depth():
    """Report how many messages are waiting in SQS."""
    if not QUEUE_URL:
        return jsonify({"error": "QUEUE_URL not configured"}), 500

    try:
        response = sqs.get_queue_attributes(
            QueueURL=QUEUE_URL,
            AttributeNames=['ApproximateNumberOfMessages',
                            'ApproximateNumberOfMessagesNotVisible']
        )
        attrs = response["Attributes"]
        return jsonify({
            "visible": int(attrs.get('ApproximateNumberOfMessages', 0)),
            "in_flight": int(attrs.get('ApproximateNumberOfMessagesNotVisible', 0))
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)