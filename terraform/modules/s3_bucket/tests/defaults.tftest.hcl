mock_provider "aws" {}

variables {
  name = "aigt-test-data"
}

run "safe_defaults" {
  command = plan

  assert {
    condition     = aws_s3_bucket.this.bucket == "aigt-test-data"
    error_message = "The bucket name must be passed through from var.name."
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
    condition     = one([for r in aws_s3_bucket_server_side_encryption_configuration.this.rule : r.apply_server_side_encryption_by_default[0].sse_algorithm]) == "AES256"
    error_message = "Server-side encryption must use AES256."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.this.block_public_acls,
      aws_s3_bucket_public_access_block.this.block_public_policy,
      aws_s3_bucket_public_access_block.this.ignore_public_acls,
      aws_s3_bucket_public_access_block.this.restrict_public_buckets,
    ])
    error_message = "All four public access block flags must be true."
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

run "tls_only_policy" {
  command = plan

  # Under the mock provider the bucket ARN, the rendered policy JSON and the
  # bucket policy attribute are unknown at plan time, so these assertions
  # target only the statement attributes that come from configuration.

  assert {
    condition     = one(data.aws_iam_policy_document.tls_only.statement).effect == "Deny"
    error_message = "The bucket policy statement must deny."
  }

  assert {
    condition     = one(data.aws_iam_policy_document.tls_only.statement).sid == "DenyInsecureTransport"
    error_message = "The bucket policy must contain the DenyInsecureTransport statement."
  }

  assert {
    condition = anytrue([
      for c in one(data.aws_iam_policy_document.tls_only.statement).condition :
      c.test == "Bool" && c.variable == "aws:SecureTransport" && contains(c.values, "false")
    ])
    error_message = "The bucket policy must deny requests where aws:SecureTransport is false."
  }

  assert {
    condition     = one(data.aws_iam_policy_document.tls_only.statement).actions == toset(["s3:*"])
    error_message = "The TLS-only statement must cover all S3 actions."
  }
}

run "force_destroy_can_be_enabled" {
  command = plan

  variables {
    force_destroy = true
  }

  assert {
    condition     = aws_s3_bucket.this.force_destroy == true
    error_message = "force_destroy = true must be honoured."
  }
}

run "accepts_3_char_name" {
  command = plan

  variables {
    name = "a1b"
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "a1b"
    error_message = "A 3-character name must be accepted."
  }
}

run "accepts_63_char_name" {
  command = plan

  variables {
    # 63 characters: "aigt-" + 58 x "a"
    name = "aigt-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }

  assert {
    condition     = length(aws_s3_bucket.this.bucket) == 63
    error_message = "A 63-character name must be accepted."
  }
}

run "rejects_uppercase" {
  command = plan

  variables {
    name = "aigt-Test-data"
  }

  expect_failures = [var.name]
}

run "rejects_underscore" {
  command = plan

  variables {
    name = "aigt_test_data"
  }

  expect_failures = [var.name]
}

run "rejects_space" {
  command = plan

  variables {
    name = "aigt test data"
  }

  expect_failures = [var.name]
}

run "rejects_leading_hyphen" {
  command = plan

  variables {
    name = "-aigt-test-data"
  }

  expect_failures = [var.name]
}

run "rejects_trailing_hyphen" {
  command = plan

  variables {
    name = "aigt-test-data-"
  }

  expect_failures = [var.name]
}

run "rejects_too_short" {
  command = plan

  variables {
    name = "ab"
  }

  expect_failures = [var.name]
}

run "rejects_too_long" {
  command = plan

  variables {
    # 64 characters: "aigt-" + 59 x "a"
    name = "aigt-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }

  expect_failures = [var.name]
}

run "rejects_empty" {
  command = plan

  variables {
    name = ""
  }

  expect_failures = [var.name]
}
