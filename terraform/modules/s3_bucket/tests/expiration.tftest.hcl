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

run "no_expiration_by_default" {
  command = plan

  assert {
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule[0].expiration) == 0
    error_message = "Current objects must not expire unless expiration_days is set."
  }
}

run "expiration_days_sets_expiry" {
  command = plan

  variables {
    expiration_days = 90
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].expiration[0].days == 90
    error_message = "expiration_days = 90 must expire current objects after 90 days."
  }
}

run "rejects_zero_days" {
  command = plan

  variables {
    expiration_days = 0
  }

  expect_failures = [var.expiration_days]
}
