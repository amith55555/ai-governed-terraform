mock_provider "aws" {}

variables {
  name = "aigt-test-bucket"
}

run "no_expiration_by_default" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule[0].expiration) == 0
    error_message = "Without expiration_days current objects must not expire."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].noncurrent_version_expiration[0].noncurrent_days == 30
    error_message = "Noncurrent versions must still expire after 30 days."
  }
}

run "expires_current_objects" {
  command = plan

  variables {
    expiration_days = 90
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].expiration[0].days == 90
    error_message = "Current objects must expire after expiration_days."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].status == "Enabled"
    error_message = "The lifecycle rule must be enabled."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].abort_incomplete_multipart_upload[0].days_after_initiation == 7
    error_message = "Incomplete multipart uploads must still be aborted."
  }
}

run "stays_private" {
  command = plan

  variables {
    expiration_days = 90
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
}

run "rejects_zero_days" {
  command = plan

  variables {
    expiration_days = 0
  }

  expect_failures = [var.expiration_days]
}

run "rejects_fractional_days" {
  command = plan

  variables {
    expiration_days = 1.5
  }

  expect_failures = [var.expiration_days]
}
