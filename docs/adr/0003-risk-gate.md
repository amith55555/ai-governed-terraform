# ADR 0003: Rule-based risk gate with human approval

- Status: Accepted
- Date: 2026-11-01

## Context

Some changes are sometimes correct but dangerous, such as deleting the
DynamoDB table. Conftest can only allow or block. We need a third answer:
"only after a human approves". The level must never be decided by an AI.

## Decision

`risk/risk_gate.py` reads each plan JSON and assigns a level from fixed rules:

| Level | Rule |
|---|---|
| high | destroy, replace or forget of `aws_dynamodb_table` or `aws_s3_bucket`; table deletion protection turned off; bucket `force_destroy` turned on |
| medium | any change to `aws_iam_*`, `aws_s3_bucket_policy` or `aws_lambda_permission` |
| low | everything else |

CI takes the highest level of dev and prod ("Risk gate"). On high, the
"Risk approval" job runs in the `risk-approval` environment and waits for
the repo owner. Both are required checks. Every push reruns them, so an
approval never carries over to new commits. 13 unit tests cover the rules.

## Not in the risk gate

Wildcard IAM and public S3 are listed as "high" in the plan, but Conftest
(ADR 0002) blocks them outright, which is stricter than an approval. Writing
the same rules again in Python would mean two copies of subtle logic.

## Consequences

- An LLM may explain the reasons in a PR, but never sets the level.
- The approval is only as strong as the identity that can click it.
  See ADR 0004.
