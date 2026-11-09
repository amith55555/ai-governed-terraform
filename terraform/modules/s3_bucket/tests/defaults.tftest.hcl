mock_provider "aws" {
  # A fixed ID and ARN, known during plan, so the policy document resolves.
  mock_resource "aws_s3_bucket" {
    override_during = plan
    defaults = {
      id  = "aigt-test-files"
      arn = "arn:aws:s3:::aigt-test-files"
    }
  }

  # The mock would otherwise return random text, which the bucket policy
  # rejects as invalid JSON. The statement itself is asserted on its inputs.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

variables {
  name = "aigt-test-files"
}

# Safe defaults: these hold for every caller, whatever the inputs.

run "safe_defaults" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == var.name
    error_message = "The bucket must be named from var.name."
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "force_destroy must be false by default."
  }

  assert {
    condition     = aws_s3_bucket_versioning.this.versioning_configuration[0].status == "Enabled"
    error_message = "Versioning must be enabled."
  }

  assert {
    condition     = one(one(aws_s3_bucket_server_side_encryption_configuration.this.rule).apply_server_side_encryption_by_default).sse_algorithm == "AES256"
    error_message = "Default encryption must be SSE-S3 (AES256)."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.block_public_acls,
      aws_s3_bucket_public_access_block.this.block_public_policy,
      aws_s3_bucket_public_access_block.this.ignore_public_acls,
      aws_s3_bucket_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "All four public access block settings must be true."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.this.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "Object ownership must be BucketOwnerEnforced (ACLs disabled)."
  }

  assert {
    condition     = one(aws_s3_bucket_lifecycle_configuration.this.rule).status == "Enabled"
    error_message = "The lifecycle rule must be enabled."
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).noncurrent_version_expiration).noncurrent_days == 30
    error_message = "Noncurrent versions must expire after 30 days."
  }

  assert {
    condition     = one(one(aws_s3_bucket_lifecycle_configuration.this.rule).abort_incomplete_multipart_upload).days_after_initiation == 7
    error_message = "Incomplete multipart uploads must be aborted after 7 days."
  }
}

# The TLS-only bucket policy.

run "tls_only_policy" {
  command = plan

  assert {
    condition     = length(data.aws_iam_policy_document.tls_only.statement) == 1
    error_message = "The bucket policy must have exactly one statement."
  }

  assert {
    condition     = data.aws_iam_policy_document.tls_only.statement[0].effect == "Deny"
    error_message = "The TLS statement must be a Deny."
  }

  assert {
    condition     = toset(data.aws_iam_policy_document.tls_only.statement[0].actions) == toset(["s3:*"])
    error_message = "The TLS statement must deny all S3 actions."
  }

  assert {
    condition = toset(data.aws_iam_policy_document.tls_only.statement[0].resources) == toset([
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ])
    error_message = "The TLS statement must cover the bucket and every object in it."
  }

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.tls_only.statement[0].condition :
      c.test == "Bool" && c.variable == "aws:SecureTransport" && toset(c.values) == toset(["false"])
    ])
    error_message = "The TLS statement must match aws:SecureTransport = false."
  }

  assert {
    condition     = aws_s3_bucket_policy.this.bucket == aws_s3_bucket.this.id
    error_message = "The policy must be attached to this bucket."
  }
}

run "force_destroy_can_be_turned_on_for_dev" {
  command = plan

  variables {
    force_destroy = true
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == true
    error_message = "force_destroy = true must be passed to the bucket."
  }
}

# Input validation: names at the limits are accepted.

run "accepts_3_character_name" {
  command = plan

  variables {
    name = "a1b"
  }
}

run "accepts_63_character_name" {
  command = plan

  variables {
    name = "aigt-dev-abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqr"
  }

  assert {
    condition     = length(var.name) == 63
    error_message = "Test setup: name must be exactly 63 characters."
  }
}

# Input validation: invalid names are rejected.

run "rejects_too_short_name" {
  command = plan

  variables {
    name = "ab"
  }

  expect_failures = [var.name]
}

run "rejects_too_long_name" {
  command = plan

  variables {
    name = "aigt-dev-abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrs"
  }

  expect_failures = [var.name]
}

run "rejects_uppercase" {
  command = plan

  variables {
    name = "aigt-dev-Files"
  }

  expect_failures = [var.name]
}

run "rejects_underscore" {
  command = plan

  variables {
    name = "aigt_dev_files"
  }

  expect_failures = [var.name]
}

run "rejects_space" {
  command = plan

  variables {
    name = "aigt dev files"
  }

  expect_failures = [var.name]
}

run "rejects_dot" {
  command = plan

  variables {
    name = "aigt.dev.files"
  }

  expect_failures = [var.name]
}

run "rejects_leading_hyphen" {
  command = plan

  variables {
    name = "-aigt-dev-files"
  }

  expect_failures = [var.name]
}

run "rejects_trailing_hyphen" {
  command = plan

  variables {
    name = "aigt-dev-files-"
  }

  expect_failures = [var.name]
}

run "rejects_empty_name" {
  command = plan

  variables {
    name = ""
  }

  expect_failures = [var.name]
}
