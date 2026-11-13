---
name: fix-policy-violation
description: Fix a failing guardrail check (Checkov, a Conftest policy, the escape-hatch policy, gitleaks, fmt, validate, tflint or terraform test) at its root cause. Use when make check or a CI check on a pull request fails.
---

# Fix a policy violation

The rule: fix the code, never the check. Do not add skips, edit `policies/`, weaken a test, or delete what the task asked for (AGENTS.md F3, F6). If you cannot fix it, stop and explain; the owner decides.

## 1. Find the exact failure

- Locally: `make check 2>&1 | tail -n 60`.
- In CI: `gh pr checks`, then `gh run view <run-id> --log-failed`, with the run ID written out (no `$`).
- Write down the check (for example `CKV_AWS_18` or `terraform.iam_wildcards`), the file and line, and the resource address.

## 2. Look up what the check wants

| The failure says | Source of truth | Usual fix |
|---|---|---|
| `CKV_AWS_*` or `CKV2_AWS_*` (make scan) | the rule name in the output; accepted findings in `docs/adr/0001-checkov-accepted-findings.md` | change the resource to meet the rule; for S3 use `terraform/modules/s3_bucket/` |
| `terraform.tags` | `policies/terraform/tags.rego` | remove the provider alias or tags override that hides the provider's `default_tags` |
| `terraform.s3_public` or `terraform.encryption` | `policies/terraform/s3_public.rego`, `policies/terraform/encryption.rego` | use `terraform/modules/s3_bucket/`: it has the access block, encryption and TLS policy |
| `terraform.iam_wildcards` | `policies/terraform/iam_wildcards.rego` | list exact actions; scope resources to ARNs passed in as variables |
| `hcl.escape_hatches` | `policies/hcl/escape_hatches.rego` | use an `aws_*` resource; module source `../../modules/<name>` |
| `hcl.iam_source` | `policies/hcl/iam_source.rego` | list exact actions as plain strings in a `data "aws_iam_policy_document"`; set `policy = data.aws_iam_policy_document.<name>.json` |
| a `terraform fmt` diff | the diff | `terraform fmt -recursive terraform/` |
| `validate` or `tflint` | the message | fix the reference, or remove the unused value |
| a `terraform test` failure | the module's `tests/*.tftest.hcl` | fix the module. Change a test only if the task changed that behaviour on purpose, and say so in the PR. |
| gitleaks `leaks found` | the redacted finding | stop. Remove the secret from the file and tell the owner: it is already in git history. |
| Risk gate `high` | `risk/risk_gate.py` | not a violation: explain the delete or replace in the PR; the owner approves |
| `Protected paths approval` waiting | `.github/workflows/guard.yml` | not a violation: the owner approves |

For a Conftest rule, read the policy and its `_test.rego` file: the tests show a passing example.

## 3. Fix, then verify

1. Change only `terraform/modules/`, `terraform/envs/` or `app/`.
2. Run `make check`. Plan policies run only in CI: push, then read `gh pr checks`.
3. If the same error comes back twice, stop and report what you tried. Do not loop.

## 4. When the finding should be accepted

Some findings are deliberate trade-offs (ADR 0001). If you think this is one, do not touch the config: explain why in the PR and leave the decision to the owner, who updates `policies/checkov/config.yml` and the ADR.
