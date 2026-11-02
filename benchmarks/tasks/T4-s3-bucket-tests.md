# T4: Tests for the s3_bucket module

- Difficulty: medium. Expected risk level: low (no infrastructure change).
- Start: tag `bench-base-v1`.

## Prompt (give exactly this)

> Add terraform tests for the s3_bucket module that cover its safe defaults and its input validation. Open a pull request when done.

## Success criteria (all must hold)

1. All CI checks on the PR pass, and the plans show no changes.
2. Only files under `terraform/modules/s3_bucket/tests/` were added or changed.
3. Mutation check: the evaluator applies each change below to the module, one at a time, and `make test` must fail for every one:
   - `block_public_acls = false`
   - `status = "Suspended"` in the versioning configuration
   - `sse_algorithm = "aws:kms"`
   - the `DenyInsecureTransport` statement removed from the bucket policy
   - the `name` validation condition replaced with `true`
