# ADR 0002: Conftest policies on the plan and the source

- Status: Accepted
- Date: 2026-10-28
- Tools: Conftest 0.71.1 (OPA 1.21.1), Rego v1

## Context

Checkov (ADR 0001) checks general AWS best practice. This project also needs
its own rules, enforced in CI, that an agent cannot talk its way around.

## Decision

Five policies, each with passing and failing unit tests (`conftest verify`):

| Policy | Input | Where it runs | What it blocks |
|---|---|---|---|
| `terraform/tags.rego` | plan JSON | Plan jobs | Taggable resources without non-empty `Project`, `Environment`, `ManagedBy` in `tags_all` |
| `terraform/s3_public.rego` | plan JSON | Plan jobs | Buckets without a full public access block, weakened blocks, public ACLs, policies that Allow `Principal "*"` |
| `terraform/encryption.rego` | plan JSON | Plan jobs | Buckets without SSE (AES256 or KMS), buckets without a TLS-only bucket policy |
| `terraform/iam_wildcards.rego` | plan JSON | Plan jobs | Allow statements with wildcard actions, `Resource "*"`, `NotAction`/`NotResource`; broad AWS managed policies |
| `hcl/escape_hatches.rego` | `.tf` source | Static checks, before `terraform init` | Provisioners; resource/data types other than `aws_*`/`archive_*`; module sources other than `../../modules/<name>`; providers other than `hashicorp/aws` and `hashicorp/archive` |

The escape-hatch policy reads source, not the plan, because `data "external"`,
`data "http"` and third-party providers run code during `init` and `plan`,
while the Plan job holds AWS credentials. `.tf.json` files are forbidden so
the HCL check cannot be skipped.

## Known limits

- Values unknown at plan time (for example ARNs of resources not created
  yet) are missing from the plan JSON. For a new bucket, the policy text
  cannot be checked (S3 R4, encryption E2); only its presence is. For a new
  IAM policy, the wildcard check is skipped with a warning. Checkov scans
  the source in both cases, and the public access block (S3 R1) makes AWS
  reject public bucket policies anyway.
- `terraform/bootstrap` is never planned in CI, so only Checkov and the
  source policy see it. Bootstrap is applied by hand and is a protected path.
- Encryption covers S3 only: DynamoDB, CloudWatch Logs and Lambda
  environment variables are always encrypted by AWS. SNS is accepted as
  unencrypted in ADR 0001.

## Rules for writing policies

- Failure messages contain only resource addresses and rule names, never
  values: the plan JSON holds the account ID and email.
- In test files, never name a helper starting with `deny`, `warn` or
  `violation`. Conftest treats those as policy rules.
- Every new rule needs at least one passing and one failing test.
