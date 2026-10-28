# ADR 0001: Checkov findings we accept

- Status: Accepted
- Date: 2026-10-28
- Scanner: Checkov 3.3.30, config in `policies/checkov/config.yml`

## Context

Checkov runs on every pull request and fails the build on any finding.
The first scan of the repo found 24 findings from 15 rules. Each rule was
reviewed and either fixed or accepted with a reason. All 15 were accepted:
most rules target large, multi-team setups, and the rest do not fit this
design or this account.

## Decision

The 15 rules below are skipped in `policies/checkov/config.yml`.
Rules are only ever skipped in that file. Inline `#checkov:skip` comments
in Terraform are not allowed, and CI fails if one appears.

| Rule | What it asks for | Why we accept it | We would change this if |
|---|---|---|---|
| CKV_AWS_145 | S3 encrypted with own KMS key | Buckets are encrypted with SSE-S3 (AWS-managed AES-256). Own keys cost about $1/month each and only add value for cross-account access control. | Another account or team needs access to the data. |
| CKV_AWS_119 | DynamoDB encrypted with own KMS key | The table is encrypted at rest by AWS. Same cost reason as above. | The table holds sensitive or personal data. |
| CKV_AWS_26 | SNS topic encrypted | CloudWatch alarms can only publish to an encrypted topic through a paid own key. Alarm messages contain no secrets. | Alarm messages start to include sensitive data. |
| CKV_AWS_158 | Log groups encrypted with own KMS key | Logs are encrypted at rest by AWS. The handler logs no personal data. | The app starts logging personal data. |
| CKV_AWS_173 | Lambda env vars encrypted with own KMS key | The variables are a table name and a bucket name. Secrets would go in Secrets Manager, not env vars. | A secret ever needs to reach the function. |
| CKV_AWS_18 | S3 access logging | Needs a second bucket that would itself need logging. CloudTrail already records changes to bucket settings. | Object-level access must be audited. |
| CKV_AWS_144 | S3 cross-region replication | Doubles cost and complexity. Versioning protects against accidental deletes. | A region outage becomes a real business risk. |
| CKV2_AWS_62 | S3 event notifications | Nothing in the system reacts to object changes. | A feature needs to react to new objects. |
| CKV_AWS_338 | Log retention of at least 1 year | 7 days in dev, 30 days in prod are enough for debugging. A year adds cost with no use here. | Compliance requires longer retention. |
| CKV_AWS_50 | Lambda X-Ray tracing | Needs IAM permissions on `Resource: "*"` in the role and the boundary, which our no-wildcard-IAM policy forbids. HTTP APIs do not support X-Ray, so only the Lambda part would be traced. | The system grows to several services where tracing pays off. |
| CKV_AWS_116 | Lambda dead-letter queue | A DLQ only receives failed asynchronous invocations. API Gateway invokes the function synchronously and returns errors to the caller, so the queue would stay empty. | The function is ever invoked asynchronously. |
| CKV_AWS_117 | Lambda inside a VPC | The 3-week version has no VPC. DynamoDB and S3 are reached over AWS endpoints with IAM. A VPC would need paid endpoints or a NAT gateway. | The function needs private resources such as RDS. |
| CKV_AWS_272 | Lambda code signing | Only CI can deploy code, and it builds it from the reviewed main branch through OIDC roles. | Code comes from outside the pipeline. |
| CKV_AWS_115 | Lambda reserved concurrency | The account's concurrency limit is 10, and AWS requires at least 10 to stay unreserved, so none can be reserved. API throttling (10 req/s, burst 20) caps load instead. | The account limit is raised. Then this becomes a fix. |
| CKV_AWS_309 | Authorization on API routes | See "Open risk" below. | See below. |

## Open risk: public API without login (CKV_AWS_309)

`GET /health` is meant to be public. `POST /items`, `GET /items` and
`GET /items/{id}` are also public today, so anyone who knows the URL can
read and write items.

Current protections:
- API throttling: 10 requests/second, burst 20, per stage.
- The URL is not published: it is a sensitive Terraform output and never
  appears in logs or PR comments.
- The Lambda role can only touch this environment's table and bucket path
  (role policy plus permissions boundary).
- Budget alert and Cost Anomaly Detection on the account.

This is the most important accepted risk in the project. The planned fix is
IAM authorization (`AWS_IAM`) on the `/items` routes, with the CI smoke test
signing its requests.

## Consequences

- Skipping a rule in the config hides it for every resource, including
  future ones. That is intended: each skip is a project-wide decision.
- Because the skip list decides what passes, `policies/checkov/config.yml`
  must be protected (CODEOWNERS and the agent hooks, in later steps).
- Any new rule failure stops the build until it is fixed or added here with
  a reason.
