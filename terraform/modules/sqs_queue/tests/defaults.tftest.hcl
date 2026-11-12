mock_provider "aws" {
  mock_resource "aws_sqs_queue" {
    override_during = plan
    defaults = {
      arn = "arn:aws:sqs:eu-central-1:123456789012:aigt-test-dlq"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

variables {
  name = "aigt-test-items"
}

run "safe_defaults" {
  command = plan

  assert {
    condition     = jsondecode(aws_sqs_queue.this.redrive_policy).maxReceiveCount == 3
    error_message = "Messages must move to the DLQ after 3 failed receives."
  }

  assert {
    condition     = aws_sqs_queue.dlq.name == "aigt-test-items-dlq"
    error_message = "The DLQ must be named <name>-dlq."
  }

  assert {
    condition     = aws_sqs_queue.this.sqs_managed_sse_enabled && aws_sqs_queue.dlq.sqs_managed_sse_enabled
    error_message = "Both queues must be encrypted at rest."
  }

  assert {
    condition     = aws_sqs_queue.dlq.message_retention_seconds == 1209600
    error_message = "The DLQ must keep messages for 14 days."
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
