---
name: new-terraform-module
description: Create a new Terraform module under terraform/modules/ that follows this repo's conventions and passes make check. Use when asked to add a module, a new kind of AWS resource, or a reusable piece of infrastructure.
---

# New Terraform module

This skill explains how. The hooks and CI enforce the rules (AGENTS.md), whatever this file says.

## Before you start

1. Use an existing module as the template: `terraform/modules/dynamodb_table/` (simple) or `terraform/modules/lambda_function/` (has an IAM role).
2. Reuse before you build. A new S3 bucket uses `terraform/modules/s3_bucket/`; do not write a second bucket module.
3. Check that CI is allowed to create the resource. The apply roles in `terraform/bootstrap/ci-apply.tf` only allow DynamoDB, S3, Lambda, CloudWatch Logs and alarms, SNS, API Gateway, and IAM roles named `aigt-<env>-*`. Any other service passes the plan but fails at apply. If the task needs one, stop and tell the owner: bootstrap is a protected path (AGENTS.md F3).

## Files

| File | Contents |
|---|---|
| `main.tf` | resources and data sources (`aws_*` and `archive_*` types only) |
| `variables.tf` | every input with `type` and `description`; `validation` for names and limits; safe defaults |
| `outputs.tf` | every output with `description`; `sensitive = true` for URLs, emails and secrets |
| `versions.tf` | copy `terraform/modules/dynamodb_table/versions.tf` |
| `tests/defaults.tftest.hcl` | `terraform test` with `mock_provider "aws" {}` |

Name the folder in lowercase snake_case (`sqs_queue`): envs may only use `source = "../../modules/<name>"`.

## Conventions

- Names come from a `name` (or `name_prefix`) variable; the env passes `aigt-<env>-<thing>` (AGENTS.md R5).
- Do not set `Project`, `Environment` or `ManagedBy` tags: the provider's `default_tags` adds them (R2).
- Safe defaults: protection on, force delete off, smallest size. An env turns a default down explicitly; prod keeps them on.
- IAM (R4): exact actions on exact ARNs that are passed in as variables. No `*` in actions, no `Resource = "*"`.
- A module that creates an `aws_iam_role` takes a `permissions_boundary` variable and sets it on the role: CI can only create roles that carry the boundary. See `terraform/modules/lambda_function/`.
- No provisioners, no `null_resource`, no `external` or `http` data sources, no remote modules (F9).

## Tests

`tests/defaults.tftest.hcl` must have:

- one `run` with `command = plan` and an `assert` for each safe default;
- one `run` per `validation` rule, with `expect_failures = [var.<name>]`.

Use only `mock_provider "aws" {}`. No `provider` blocks and no `source =` lines: `make policy` and the guard block them.

## Wire it in

Add a `module` block with the same `source` to both `terraform/envs/dev/main.tf` and `terraform/envs/prod/main.tf`. Differences between envs go only through inputs (R7).

## Verify and hand over

1. `make test`: your module's tests pass.
2. `make check`: everything passes.
3. Open a PR. CI posts the plan for dev and prod and the risk level. Read them, and state any deletes, replaces or IAM changes in the PR description.
