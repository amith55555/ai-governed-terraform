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
    condition     = length(aws_s3_bucket_lifecycle_configuration.this.rule) == 1
    error_message = "Without expiration_days, only the noncurrent-version rule must exist."
  }
}

run "expiration_days_adds_rule" {
  command = plan

  variables {
    expiration_days = 90
  }

  assert {
    condition     = length([for r in aws_s3_bucket_lifecycle_configuration.this.rule : r if r.id == "ExpireObjects" && r.status == "Enabled" && r.expiration[0].days == 90]) == 1
    error_message = "expiration_days = 90 must add an enabled ExpireObjects rule with 90 days."
  }
}

run "rejects_zero_expiration" {
  command = plan

  variables {
    expiration_days = 0
  }

  expect_failures = [var.expiration_days]
}
