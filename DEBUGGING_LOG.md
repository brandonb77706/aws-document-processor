# Debugging Log — AWS Document Processor

A record of real bugs hit while building the S3 → Lambda → Textract → SQS pipeline, what caused them, and how they were solved. Useful for interview prep ("tell me about a tricky bug you debugged").

---

## Challenge 1: Terraform "inconsistent final plan" error when adding environment variables to existing Lambda

**Phase:** 2
**Symptom:** Running `terraform apply` to add an `environment` block to an already-deployed Lambda failed mid-apply with:

```
Error: Provider produced inconsistent final plan
... block count changed from 0 to 1 ...
```

**Root cause:** A known bug in the AWS Terraform provider. When adding a new optional block (like `environment`) to a resource that didn't previously have one, the provider sometimes confuses itself between "block exists with zero items" and "block doesn't exist." It's a provider-side issue, not a code mistake.

**Fix:** Just re-ran `terraform apply`. Terraform's state had been partially updated on the first run, so the second run had a consistent starting point and succeeded.

**Lesson:** Not every Terraform error means your code is wrong. Some are provider quirks. "Run it again" is a legitimate first move when state seems inconsistent. If a re-run doesn't fix it, escalate to `terraform apply -refresh-only` or tainting the resource.

---

## Challenge 2: IAM permission denied with misleading error message

**Phase:** 3
**Symptom:** Lambda was getting this error from Textract:

```
InvalidS3ObjectException: Unable to get object metadata from S3.
Check object key, region and/or access permissions.
```

This persisted across multiple test files — a 41KB receipt, a 1.9MB screenshot, a 138KB PDF. The error suggested the file didn't exist, but `aws s3 ls` confirmed every file was there.

**Root cause:** The IAM policy granting Lambda permission to read from S3 had a typo in the resource ARN:

```
"Resource": "arn:aws:s3:::doc-processor-uploads-6b847f2f/"
```

It should have been:

```
"Resource": "arn:aws:s3:::doc-processor-uploads-6b847f2f/*"
```

The trailing `/` (instead of `/*`) granted permission to a single object whose key was the empty string — which doesn't exist — instead of all objects in the bucket. So Lambda had zero useful S3 permissions, Textract called S3 on Lambda's behalf, got denied, and AWS returned a generic "InvalidS3ObjectException."

**How I diagnosed it:** When the file size and format were ruled out as the cause, I ran three diagnostic commands:

```
aws s3api get-bucket-location --bucket <bucket>
aws iam list-role-policies --role-name doc-processor-lambda-role
aws iam get-role-policy --role-name doc-processor-lambda-role --policy-name lambda-textract-call
```

The third command revealed the bad resource ARN.

**Fix:** Updated the Terraform to ensure the wildcard was present:

```hcl
Resource = "${aws_s3_bucket.uploads.arn}/*"
```

Re-applied, re-uploaded, error went away.

**Lessons:**

- AWS error messages can be actively misleading. "Unable to get object metadata" actually meant "permission denied for any object in this bucket."
- Cross-service IAM is a common debugging trap. Textract called S3 _as Lambda's role_, so Lambda needed S3 permissions even though the user (me) was the one uploading the file.
- The S3 IAM model has two distinct resource types: the bucket itself (`arn:...:bucket`) and the objects in it (`arn:...:bucket/*`). They are separate ARNs and require separate permissions for the corresponding actions. This was the cause of the Capital One 2019 breach (over-permissioned `s3:*` on `*`).
- When debugging permissions, dump the actual policy from IAM rather than trusting what you think the Terraform produced.

---

## Challenge 3: Lambda timeout when calling Textract

**Phase:** 3
**Symptom:** After fixing the IAM bug, Lambda started failing with:

```
Status: timeout
Duration: 3000.00 ms
```

This happened on a 237KB receipt image. Smaller files worked, larger ones didn't.

**Root cause:** Lambda's default execution timeout is 3 seconds. Textract's synchronous `detect_document_text` API takes 2-5 seconds for an average document — longer for detailed images. Lambda was killing the function mid-Textract-call.

**Fix:** Updated the Lambda configuration in Terraform to bump the timeout and memory:

```hcl
resource "aws_lambda_function" "processor" {
  ...
  timeout     = 60
  memory_size = 512
}
```

More memory also gives proportionally more CPU, which speeds up response parsing.

**Lessons:**

- Lambda's default 3-second timeout is fine for trivial functions but inadequate for any real work involving downstream API calls.
- Hitting Lambda's timeout is a smell that you may eventually outgrow Lambda for that workload. Lambda's hard 15-minute max means long-running OCR/processing jobs eventually need containers (ECS Fargate, EC2).
- Memory and CPU are linked in Lambda — bumping memory often improves performance and isn't always more expensive overall (faster execution = less time billed).

---

## Challenge 4: Silent string-mismatch bug — Textract worked, but my code returned 0 results

**Phase:** 3
**Symptom:** After fixing IAM and timeout, every upload returned:

```
Extracted 0 lines, 0 characters
```

Lambda completed successfully (~3-4 seconds, no errors), Textract was being called, the response was returning data — but my code reported zero extracted lines. Tried multiple file formats (JPG, PNG, PDF), multiple sources (screenshots, downloaded receipts, my own resume PDF). All returned 0 lines.

**Root cause:** A case-sensitive string comparison bug:

```python
if block['BlockType'] == 'Line'    # WRONG — Textract returns 'LINE'
```

Textract returns block types in all caps (`LINE`, `WORD`, `PAGE`). My filter was looking for `'Line'`, so it never matched any block, and `lines` was always an empty list. The code didn't crash because filtering an empty list is valid Python — it just silently produced empty results.

**How I diagnosed it:** Once I suspected the bug was in my code rather than infrastructure, the plan was to dump the raw Textract response with debug logging — counting block types and printing the first few raw blocks. Before deploying that, I re-read my code and spotted the case mismatch directly.

**Fix:**

```python
if block['BlockType'] == 'LINE'    # CORRECT
```

Re-deployed, uploaded resume.pdf, and got back 59 lines / 4050 characters of extracted text — including my name, GPA, and university.

**Lessons:**

- Silent string mismatches are some of the worst bugs in software. The code runs, the API succeeds, the response has data — but a single typo in a comparison filters everything out. No exceptions, no crashes, just empty results.
- When an external API "succeeds but returns nothing useful," the first move should always be to dump the raw response and inspect what it actually contains. Don't trust your assumption about the structure.
- Case sensitivity in API field values is non-obvious until you check the docs (or print the response). Different AWS services use different conventions — sometimes `PascalCase`, sometimes `UPPER_SNAKE`, sometimes lowercase.
- "It runs without errors but returns nothing" is a more dangerous failure mode than a crash, because it doesn't trigger your attention.

---

## General lessons from Phases 1-3

1. **Read the actual data, not what you think the data is.** Most of these bugs would have been caught immediately by dumping raw API responses and IAM policies rather than reasoning about what they "should" contain.

2. **AWS error messages often lie.** "InvalidS3ObjectException" meant "permission denied." "Status: timeout" meant "your function is fine but you didn't give it enough time." Treat error messages as starting points, not conclusions.

3. **Cross-service permissions are the most common debugging trap.** When service A calls service B on your behalf, A needs permissions for B's resources. The user uploading a file is irrelevant — Lambda's role is what matters.

4. **Infrastructure-as-code makes debugging easier.** Every fix was a small Terraform change followed by `terraform apply`. No clicking through console menus, no losing track of what changed. Git history shows exactly what fixed each bug.

5. **The pipeline can work even when individual stages look broken.** Multiple times I thought "the whole thing is broken" when really one tiny piece was wrong. Isolating which stage was actually failing — versus which were just downstream of a failure — was key.
