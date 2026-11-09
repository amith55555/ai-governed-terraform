mock_provider "aws" {}

variables {
  name = "aigt-test-items-12345678"
}

run "safe_defaults" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 1
    error_message = "By default there must be only the ExpireOldVersions rule."
  }

  assert {
    condition     = length([for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if r.id == "ExpireObjects"]) == 0
    error_message = "By default there must be no ExpireObjects rule."
  }

  assert {
    condition = (
      aws_s3_bucket_public_access_block.this.block_public_acls == true &&
      aws_s3_bucket_public_access_block.this.block_public_policy == true &&
      aws_s3_bucket_public_access_block.this.ignore_public_acls == true &&
      aws_s3_bucket_public_access_block.this.restrict_public_buckets == true
    )
    error_message = "All four public access block settings must be true."
  }
}

run "expiration_days_adds_rule" {
  command = plan

  variables {
    expiration_days = 90
  }

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 2
    error_message = "expiration_days must add exactly one rule next to ExpireOldVersions."
  }

  assert {
    condition = anytrue([
      for r in aws_s3_bucket_lifecycle_configuration.this.rule :
      r.id == "ExpireObjects" && r.expiration[0].days == 90
    ])
    error_message = "There must be an ExpireObjects rule expiring objects after 90 days."
  }
}

run "rejects_invalid_expiration_days" {
  command = plan

  variables {
    expiration_days = 0
  }

  expect_failures = [var.expiration_days]
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "bad name"
  }

  expect_failures = [var.name]
}
