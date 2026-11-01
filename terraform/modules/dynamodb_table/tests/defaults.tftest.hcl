mock_provider "aws" {}

variables {
  name = "aigt-test-items"
}

run "safe_defaults" {
  command = plan

  assert {
    condition     = aws_dynamodb_table.this.deletion_protection_enabled == true
    error_message = "Deletion protection must be on by default."
  }

  assert {
    condition     = aws_dynamodb_table.this.point_in_time_recovery[0].enabled == true
    error_message = "Point-in-time recovery must be on."
  }

  assert {
    condition     = aws_dynamodb_table.this.billing_mode == "PAY_PER_REQUEST"
    error_message = "Billing mode must be on-demand (PAY_PER_REQUEST)."
  }

  assert {
    condition     = aws_dynamodb_table.this.hash_key == "id"
    error_message = "The partition key must be \"id\" (the handler depends on it)."
  }
}

run "protection_can_be_turned_off_for_dev" {
  command = plan

  variables {
    deletion_protection = false
  }

  assert {
    condition     = aws_dynamodb_table.this.deletion_protection_enabled == false
    error_message = "deletion_protection = false must turn protection off."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "bad name"
  }

  expect_failures = [var.name]
}
