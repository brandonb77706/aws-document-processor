# AWS Document Processor

Event-driven document processing pipeline on AWS.

## Current Status

- Phase 1: S3 to Lambda trigger ✓
- Phase 2: Lambda enqueues to SQS ✓
- Phase 3: Worker processes documents with Textract (in progress)

## Stack

- Terraform for infrastructure as code
- AWS Lambda (Python 3.12)
- Amazon S3, SQS
