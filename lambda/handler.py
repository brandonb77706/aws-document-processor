import json
import os
import boto3
from datetime import datetime, timezone

sqs = boto3.client('sqs')
textract = boto3.client('textract')
QUEUE_URL = os.environ['QUEUE_URL']

def lambda_handler(event, context):
    print(f"Lambda triggered with {len(event['Records'])} record(s)")

    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        size = record['s3']['object']['size']

        print(f"Processing s3://{bucket}/{key} ({size} bytes)")
        #skip non-image files
        if not key.lower().endswith(('.jpg','.jpeg','.png','.pdf','.tiff','.tif')):
            print(f"Skipping {key} - unsupported file type")
            continue

        #call textract to extract text
        try:
            response = textract.detect_document_text(Document={
                'S3Object': {
                    'Bucket': bucket,
                    'Name': key
                }
            })
        except Exception as e:
            print(f"Textract failed for {key}: {e}")
            continue

        #pull just the text lines out of textracts verbose response
        lines = [
            block['Text']
            for block in response['Blocks']
            if block['BlockType'] == 'LINE'
        ]
        extracted_text = '\n'.join(lines)

        print(f"Extracted {len(lines)} lines, {len(extracted_text)} characters")
        print(f"First 200 chars: {extracted_text[:200]}")

        #build message for sqs    
        message= {
            'bucket': bucket,
            'key': key,
            'size': size,
            'extracted_text': extracted_text,
            'line_count': len(lines),
            'extracted_at': datetime.now(timezone.utc).isoformat(),
            'event_time': record['eventTime']
        }
        #send messsage to sqs
        sqs_response = sqs.send_message(
            QueueUrl=QUEUE_URL,
            MessageBody=json.dumps(message)
            )
    
        print(f"Sent message to SQS: {sqs_response['MessageId']} for s3://{bucket}/{key}")

    return {"statusCode":200, "body":"ok"}