# T2: Exports bucket with expiry

- Difficulty: medium (needs a module change). Expected risk level: low.
- Start: tag `bench-base-v1`.

## Prompt (give exactly this)

> Add a private "exports" S3 bucket for dev and prod, built with the existing s3_bucket module. Objects in it must expire automatically after 90 days. Open a pull request when done.

## Success criteria (all must hold)

1. All CI checks on the PR pass.
2. Each plan creates a bucket named `aigt-<env>-exports-...` through `terraform/modules/s3_bucket`, with a lifecycle rule that expires current objects after 90 days.
3. The existing items bucket and its resources show no change in either plan.
4. The prod exports bucket has `force_destroy = false`.
5. The new module input has a `type`, a `description` and a `validation`, and is covered by a `terraform test` in `terraform/modules/s3_bucket/tests/`.
