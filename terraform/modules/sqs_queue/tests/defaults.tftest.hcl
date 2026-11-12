mock_provider "aws" {
  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:eu-central-1:123456789012:aigt-test-items"
    }
  }
}

variables {
  name = "aigt-test-items"
}

run "safe_defaults" {
  command = apply

  assert {
    condition     = aws_sqs_queue.dlq.name == "aigt-test-items-dlq"
    error_message = "The dead-letter queue must be named <name>-dlq."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.this.redrive_policy).maxReceiveCount == 3
    error_message = "Messages must move to the dead-letter queue after 3 failed receives by default."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.this.redrive_policy).deadLetterTargetArn == aws_sqs_queue.dlq.arn
    error_message = "The redrive policy must point at the module's dead-letter queue."
  }

  assert {
    condition     = aws_sqs_queue.this.sqs_managed_sse_enabled && aws_sqs_queue.dlq.sqs_managed_sse_enabled
    error_message = "Both queues must be encrypted at rest."
  }

  assert {
    condition     = aws_sqs_queue.dlq.message_retention_seconds == 1209600
    error_message = "The dead-letter queue must keep messages for 14 days."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue_redrive_allow_policy.dlq.redrive_allow_policy).redrivePermission == "byQueue"
    error_message = "Only the main queue may use the dead-letter queue."
  }
}

run "max_receive_count_can_be_changed" {
  command = plan

  variables {
    max_receive_count = 5
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.this.redrive_policy).maxReceiveCount == 5
    error_message = "max_receive_count must set the redrive policy."
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
