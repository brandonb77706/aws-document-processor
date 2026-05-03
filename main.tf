terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "uploads" {
  bucket = "doc-processor-uploads-${random_id.suffix.hex}"
}

resource "aws_iam_role" "lambda_role" {
  name = "doc-processor-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "processor" {
  function_name    = "doc-processor"
  role             = aws_iam_role.lambda_role.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  timeout = 60
  #more cpu usage
  memory_size = 512


  environment {
    variables = {
        QUEUE_URL = aws_sqs_queue.doc_queue.url
    }
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.uploads.arn
}

resource "aws_s3_bucket_notification" "upload_trigger" {
  bucket = aws_s3_bucket.uploads.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.processor.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

resource "aws_iam_role_policy" "lambda_textract" {
  name = "lambda-textract-call"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "textract:DetectDocumentText"
        Resource = "*"
      },{
        Effect = "Allow"
        Action = "s3:GetObject"
        Resource = "${aws_s3_bucket.uploads.arn}/*"
      }
    ]
  })
}
#SQS queue for documents waiting to be processed
resource "aws_sqs_queue" "doc_queue" {
    name = "doc-processing-queue"
    visibility_timeout_seconds = 300 # 5 mins for worker to be process before message reappers
    message_retention_seconds = 1209600  # 14 days max retention
}
#policy allowing Lambda to send messages to the queue
resource "aws_iam_role_policy" "lambda_sqs_send" {
    name = "lambda-sqs-send"
    role = aws_iam_role.lambda_role.id

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
            Effect = "Allow"
            Action = "sqs:SendMessage"
            Resource = aws_sqs_queue.doc_queue.arn
        }]
    })
}
#output for bucket name
output "bucket_name" {
  value = aws_s3_bucket.uploads.bucket
}

#output the queue url so we can interact with it.
output "queue_url" {
    value = aws_sqs_queue.doc_queue.url
}