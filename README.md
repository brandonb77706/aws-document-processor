A file uploaded to S3 triggers a Lambda function, which calls Amazon Textract to extract text from the document, then publishes the structured result to an SQS queue. The queue decouples ingestion from downstream processing — future workers can consume results at their own pace without coupling to the upload flow.

## Progress

- ✅ Phase 1: S3 → Lambda event-driven pipeline
- ✅ Phase 2: SQS integration for decoupled processing
- ✅ Phase 3: Textract OCR with extracted text published to queue
- 🚧 Phase 4: VPC and networking foundation
- ⏳ Phase 5: Containerized workers on Fargate behind an ALB
- ⏳ Phase 6: DynamoDB and OpenSearch for storage and search
- ⏳ Phase 7: Frontend, HTTPS, and custom domain

## Stack

- **Infrastructure as code:** Terraform
- **Compute:** AWS Lambda (Python 3.12)
- **Storage:** Amazon S3
- **Messaging:** Amazon SQS
- **AI/ML:** Amazon Textract
- **Identity:** IAM with least-privilege role policies
- **Observability:** CloudWatch Logs

## Design decisions

**Why event-driven instead of synchronous?** S3 upload events trigger Lambda asynchronously, so users get immediate confirmation while OCR happens in the background. The file is durably stored before processing begins, so failures can be retried without losing data.

**Why SQS between Lambda and downstream consumers?** Decoupling. Lambda's job is event handling — it fires fast and finishes. Downstream consumers (future Fargate workers) can scale and process at their own pace. Either side can be modified or replaced without touching the other.

**Why Lambda for Textract calls in the current phase?** Lambda is event-native and scales to zero, which is ideal for sporadic upload traffic. This will be moved to Fargate in Phase 5 once long-running multi-page document processing exceeds Lambda's 15-minute timeout — a real architectural transition, not a rewrite.

## Repository structure

## Local setup

Requires AWS CLI, Terraform, and an AWS account with appropriate IAM credentials configured.

```bash
terraform init
terraform plan
terraform apply
```

To test:

```bash
aws s3 cp <file> s3://$(terraform output -raw bucket_name)/<file>
aws logs tail /aws/lambda/doc-processor --follow
```

## Cost

Designed to run within AWS Free Tier limits during development. Approximate cost at moderate usage:

- Lambda: free for first 1M invocations/month
- S3: pennies for typical document storage
- SQS: free for first 1M requests/month
- Textract: $1.50 per 1,000 pages (no free tier)

Total cost during development has been under $1.
