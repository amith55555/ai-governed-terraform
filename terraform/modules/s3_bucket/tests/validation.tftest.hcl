mock_provider "aws" {}

# Valid names: shortest and longest allowed, digits and hyphens.

run "accepts_minimum_length_name" {
  command = plan

  variables {
    name = "abc"
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "abc"
    error_message = "A 3-character name must be accepted."
  }
}

run "accepts_maximum_length_name" {
  command = plan

  variables {
    name = "a${join("", [for i in range(61) : "b"])}c"
  }

  assert {
    condition     = length(aws_s3_bucket.this.bucket) == 63
    error_message = "A 63-character name must be accepted."
  }
}

run "accepts_digits_and_hyphens" {
  command = plan

  variables {
    name = "0-app-data-2026"
  }

  assert {
    condition     = aws_s3_bucket.this.bucket == "0-app-data-2026"
    error_message = "Digits and hyphens must be accepted."
  }
}

# Invalid names: each one must fail the validation on var.name.

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
    name = "a${join("", [for i in range(62) : "b"])}c"
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

run "rejects_uppercase" {
  command = plan

  variables {
    name = "My-Bucket"
  }

  expect_failures = [var.name]
}

run "rejects_underscore" {
  command = plan

  variables {
    name = "my_bucket"
  }

  expect_failures = [var.name]
}

run "rejects_space" {
  command = plan

  variables {
    name = "my bucket"
  }

  expect_failures = [var.name]
}

run "rejects_dot" {
  command = plan

  variables {
    name = "my.bucket"
  }

  expect_failures = [var.name]
}

run "rejects_leading_hyphen" {
  command = plan

  variables {
    name = "-my-bucket"
  }

  expect_failures = [var.name]
}

run "rejects_trailing_hyphen" {
  command = plan

  variables {
    name = "my-bucket-"
  }

  expect_failures = [var.name]
}
