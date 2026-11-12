mock_provider "aws" {}

# The mock returns random strings; queue policies need valid JSON.
override_data {
  target = data.aws_iam_policy_document.tls_only
  values = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
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
    error_message = "The redrive policy must point at this module's dead-letter queue."
  }

  assert {
    condition     = aws_sqs_queue.this.sqs_managed_sse_enabled && aws_sqs_queue.dlq.sqs_managed_sse_enabled
    error_message = "Both queues must be encrypted at rest."
  }

  assert {
    condition     = aws_sqs_queue.dlq.message_retention_seconds == 1209600
    error_message = "The dead-letter queue must keep messages for the maximum 14 days."
  }

  assert {
    condition     = aws_sqs_queue_policy.this.queue_url == aws_sqs_queue.this.id && aws_sqs_queue_policy.dlq.queue_url == aws_sqs_queue.dlq.id
    error_message = "Both queues must have a TLS-only queue policy."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "bad name"
  }

  expect_failures = [var.name]
}

run "rejects_invalid_max_receive_count" {
  command = plan

  variables {
    max_receive_count = 0
  }

  expect_failures = [var.max_receive_count]
}

run "rejects_invalid_message_retention" {
  command = plan

  variables {
    message_retention_seconds = 30
  }

  expect_failures = [var.message_retention_seconds]
}

run "rejects_invalid_visibility_timeout" {
  command = plan

  variables {
    visibility_timeout_seconds = 50000
  }

  expect_failures = [var.visibility_timeout_seconds]
}
