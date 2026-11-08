# The mock would otherwise return a random string for json, which the
# bucket policy rejects as invalid JSON during apply.
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
    condition     = aws_s3_bucket.this.bucket == var.name
    error_message = "The bucket must use the name passed in."
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
    error_message = "All four public access block settings must be on."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.this.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "Object ownership must be BucketOwnerEnforced (ACLs disabled)."
  }
}

run "tls_only_bucket_policy" {
  command = apply

  assert {
    condition     = length(data.aws_iam_policy_document.tls_only.statement) == 1
    error_message = "The bucket policy must have exactly one statement."
  }

  assert {
    condition = (
      data.aws_iam_policy_document.tls_only.statement[0].effect == "Deny" &&
      toset(data.aws_iam_policy_document.tls_only.statement[0].actions) == toset(["s3:*"])
    )
    error_message = "The policy must deny all S3 actions."
  }

  assert {
    condition = anytrue([
      for p in data.aws_iam_policy_document.tls_only.statement[0].principals :
      p.type == "*" && toset(p.identifiers) == toset(["*"])
    ])
    error_message = "The deny must apply to every principal."
  }

  assert {
    condition = anytrue([
      for c in data.aws_iam_policy_document.tls_only.statement[0].condition :
      c.test == "Bool" && c.variable == "aws:SecureTransport" && toset(c.values) == toset(["false"])
    ])
    error_message = "The deny must apply only to requests without TLS (aws:SecureTransport = false)."
  }

  assert {
    condition = toset(data.aws_iam_policy_document.tls_only.statement[0].resources) == toset([
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ])
    error_message = "The deny must cover the bucket and all of its objects."
  }
}

run "tls_policy_attached_to_bucket" {
  command = apply

  assert {
    condition     = aws_s3_bucket_policy.this.bucket == aws_s3_bucket.this.id
    error_message = "The TLS-only policy must be attached to this bucket."
  }

  assert {
    condition     = aws_s3_bucket_policy.this.policy == data.aws_iam_policy_document.tls_only.json
    error_message = "The bucket policy must be the TLS-only policy document."
  }

  assert {
    condition = (
      aws_s3_bucket_versioning.this.bucket == aws_s3_bucket.this.id &&
      aws_s3_bucket_server_side_encryption_configuration.this.bucket == aws_s3_bucket.this.id &&
      aws_s3_bucket_public_access_block.this.bucket == aws_s3_bucket.this.id &&
      aws_s3_bucket_ownership_controls.this.bucket == aws_s3_bucket.this.id &&
      aws_s3_bucket_lifecycle_configuration.this.bucket == aws_s3_bucket.this.id
    )
    error_message = "Every bucket setting must be attached to this bucket."
  }
}

run "lifecycle_cleans_up_old_data" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 1
    error_message = "By default there must be exactly one lifecycle rule."
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

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule[0].expiration) == 0
    error_message = "Current object versions must not expire by default."
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

# Name validation: accepted boundaries.

run "accepts_three_character_name" {
  command = plan

  variables {
    name = "a1b"
  }
}

run "accepts_sixty_three_character_name" {
  command = plan

  variables {
    name = "a23456789012345678901234567890123456789012345678901234567890123"
  }
}

# Name validation: rejected inputs.

run "rejects_two_character_name" {
  command = plan

  variables {
    name = "ab"
  }

  expect_failures = [var.name]
}

run "rejects_sixty_four_character_name" {
  command = plan

  variables {
    name = "a234567890123456789012345678901234567890123456789012345678901234"
  }

  expect_failures = [var.name]
}

run "rejects_uppercase_name" {
  command = plan

  variables {
    name = "Aigt-bucket"
  }

  expect_failures = [var.name]
}

run "rejects_name_with_space" {
  command = plan

  variables {
    name = "bad name"
  }

  expect_failures = [var.name]
}

run "rejects_name_with_underscore" {
  command = plan

  variables {
    name = "aigt_bucket"
  }

  expect_failures = [var.name]
}

run "rejects_name_with_dot" {
  command = plan

  variables {
    name = "aigt.bucket"
  }

  expect_failures = [var.name]
}

run "rejects_leading_hyphen" {
  command = plan

  variables {
    name = "-aigt-bucket"
  }

  expect_failures = [var.name]
}

run "rejects_trailing_hyphen" {
  command = plan

  variables {
    name = "aigt-bucket-"
  }

  expect_failures = [var.name]
}
