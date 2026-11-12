mock_provider "aws" {
  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:eu-central-1:123456789012:aigt-test-items-dlq"
    }
  }
}

variables {
  name = "aigt-test-items"
}

run "safe_defaults" {
  command = apply

  assert {
    condition     = aws_sqs_queue.this.sqs_managed_sse_enabled == true && aws_sqs_queue.dlq.sqs_managed_sse_enabled == true
    error_message = "Both queues must be encrypted."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.this.redrive_policy).maxReceiveCount == 3
    error_message = "Messages must move to the dead-letter queue after 3 failed receives."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.this.redrive_policy).deadLetterTargetArn == aws_sqs_queue.dlq.arn
    error_message = "The redrive policy must point at the module's dead-letter queue."
  }

  assert {
    condition     = aws_sqs_queue.dlq.name == "aigt-test-items-dlq"
    error_message = "The dead-letter queue must be named <name>-dlq."
  }

  assert {
    condition     = aws_sqs_queue.dlq.message_retention_seconds > aws_sqs_queue.this.message_retention_seconds
    error_message = "The dead-letter queue must keep messages longer than the main queue."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "bad name"
  }

  expect_failures = [var.name]
}

run "rejects_zero_receive_count" {
  command = plan

  variables {
    max_receive_count = 0
  }

  expect_failures = [var.max_receive_count]
}

run "rejects_too_long_visibility_timeout" {
  command = plan

  variables {
    visibility_timeout_seconds = 50000
  }

  expect_failures = [var.visibility_timeout_seconds]
}

run "rejects_too_long_retention" {
  command = plan

  variables {
    message_retention_seconds = 2000000
  }

  expect_failures = [var.message_retention_seconds]
}

run "rejects_too_long_dlq_retention" {
  command = plan

  variables {
    dlq_message_retention_seconds = 2000000
  }

  expect_failures = [var.dlq_message_retention_seconds]
}
