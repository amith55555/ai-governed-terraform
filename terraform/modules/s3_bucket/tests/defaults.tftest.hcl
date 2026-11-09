# The mock provider fills computed attributes with random strings, which the
# provider rejects as a bucket policy. Return valid JSON for the policy document.
mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  name = "aigt-test-bucket"
}

run "safe_defaults" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "aigt-test-bucket"
    error_message = "The bucket must be named after var.name."
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == false
    error_message = "force_destroy must be off by default."
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
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].status == "Enabled"
    error_message = "The lifecycle rule must be enabled."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].noncurrent_version_expiration[0].noncurrent_days == 30
    error_message = "Noncurrent versions must expire after 30 days."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].abort_incomplete_multipart_upload[0].days_after_initiation == 7
    error_message = "Incomplete multipart uploads must be aborted after 7 days."
  }
}

# The policy statement references the bucket ARN, which is unknown at plan
# time, so this run applies against the mock provider.
run "bucket_policy_denies_insecure_transport" {
  command = apply

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
    error_message = "The TLS statement must cover all S3 actions."
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
      for p in data.aws_iam_policy_document.tls_only.statement[0].principals :
      p.type == "*" && toset(p.identifiers) == toset(["*"])
    ])
    error_message = "The TLS statement must apply to every principal."
  }

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.tls_only.statement[0].condition :
      c.test == "Bool" && c.variable == "aws:SecureTransport" && toset(c.values) == toset(["false"])
    ])
    error_message = "The TLS statement must deny requests where aws:SecureTransport is false."
  }

  assert {
    condition     = aws_s3_bucket_policy.this.policy == data.aws_iam_policy_document.tls_only.json
    error_message = "The bucket policy must be the TLS-only policy document."
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

# --- Name validation: accepted edge cases ---

run "accepts_minimum_length_name" {
  command = plan

  variables {
    name = "a1b"
  }
}

run "accepts_maximum_length_name" {
  command = plan

  variables {
    name = "abbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbz" # 63 chars
  }
}

# --- Name validation: rejected names ---

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
    name = "abbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbz" # 64 chars
  }

  expect_failures = [var.name]
}

run "rejects_uppercase_name" {
  command = plan

  variables {
    name = "Aigt-test-bucket"
  }

  expect_failures = [var.name]
}

run "rejects_leading_hyphen" {
  command = plan

  variables {
    name = "-aigt-test-bucket"
  }

  expect_failures = [var.name]
}

run "rejects_trailing_hyphen" {
  command = plan

  variables {
    name = "aigt-test-bucket-"
  }

  expect_failures = [var.name]
}

run "rejects_underscore" {
  command = plan

  variables {
    name = "aigt_test_bucket"
  }

  expect_failures = [var.name]
}

run "rejects_space" {
  command = plan

  variables {
    name = "aigt test bucket"
  }

  expect_failures = [var.name]
}

run "rejects_dot" {
  command = plan

  variables {
    name = "aigt.test.bucket"
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
