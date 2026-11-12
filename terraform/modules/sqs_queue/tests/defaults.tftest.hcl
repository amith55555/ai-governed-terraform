mock_provider "aws" {
  mock_resource "aws_sqs_queue" {
    defaults = {
      arn = "arn:aws:sqs:eu-central-1:111111111111:aigt-test-items-dlq"
    }
  }
}

variables {
  name            = "aigt-test-items"
  alarm_topic_arn = "arn:aws:sns:eu-central-1:111111111111:aigt-test-alarms"
}

run "queues_are_encrypted_with_a_dead_letter_queue" {
  command = apply

  assert {
    condition     = aws_sqs_queue.this.sqs_managed_sse_enabled && aws_sqs_queue.dead_letter.sqs_managed_sse_enabled
    error_message = "Both queues must be encrypted."
  }

  assert {
    condition     = jsondecode(aws_sqs_queue.this.redrive_policy).maxReceiveCount == 3
    error_message = "Messages must move to the dead-letter queue after 3 receives."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.dead_letter_messages.namespace == "AWS/SQS"
    error_message = "The alarm must watch the dead-letter queue."
  }
}
