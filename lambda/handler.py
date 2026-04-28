import json
import os
import boto3

sqs = boto3.client('sqs')
QUEUE_URL = os.environ['QUEUE_URL']

def lambda_handler(event, context):
    print(f"Lambda triggered with {len(event['Records'])} record(s)")

    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        size = record['s3']['object']['size']

        message= {
            'bucket': bucket,
            'key': key,
            'size': size,
            'event_time': record['eventTime']
        }

    response = sqs.send_message(
        QueueUrl=QUEUE_URL,
        MessageBody=json.dumps(message)
        )
    
    print(f"Sent message to SQS: {response['MessageId']} for s3://{bucket}/{key}")

    return {"statusCode":200, "body":"ok"}